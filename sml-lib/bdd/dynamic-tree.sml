(* Copyright 2010 Tom Murphy VII and Erin Catto. See COPYING for details. *)

(* A dynamic AABB tree for the broad-phase collision detection.
   Corresponding to collision/b2dynamictree.cpp. *)
structure BDDDynamicTree :> BDDDYNAMIC_TREE =
struct
  open BDDSettings
  open BDDTypes
  open BDDMath
  open BDDOps
  infix 6 :+: :-: %-% %+% +++
  infix 7 *: *% +*: +*+ #*% @*:

  exception BDDDynamicTree of string

  (* Port note: Corresponds to DynamicTreeNode in b2dynamictree.h.
     I decided to use more idiomatic SML instead of the hand-written
     allocator in Box2D, since it's not clear it'd be faster than
     a good generational gc. *)

  datatype child_direction = Left | Right

  datatype 'a tree_node =
      Node of 'a interior_node
    | Leaf of 'a leaf_node
  and 'a interior_node =
      Nd of { (* Fattened aabb *)
                aabb : aabb ref,
                (* Port note: Box2D has a possibility for
                   a 'next' pointer here, but it's just
                   so that the structure can be stored
                   in freelists for its custom allocator. *)
                parent : 'a parent ref,
                left : 'a tree_node ref,
                right : 'a tree_node ref,
                height : int ref}
  and 'a leaf_node =
      Lf of { (* Fattened aabb *)
                aabb : aabb ref,
                parent : 'a parent ref,
                (* XXX overflow possibility *)
                stamp : int,
                data : 'a }
  and 'a parent = NoParent
                | Parent of 'a interior_node * child_direction


  type 'a aabb_proxy = 'a leaf_node

  (* Port note: The representation is that leaf nodes are the
     "real" nodes (and have user data) whereas internal nodes just
     union up leaves to arrange them hierarchically, and are expendable. *)
  (* Represent the whole thing as a ref so that we don't confuse the
     updateable root pointer with the identity of the node contained
     there. *)
  type 'a dynamic_tree =
      { node_count : int,
        root : 'a tree_node option } ref

  (* PERF just for debugging. *)
  fun checkstructure s (r as (Leaf _ )) = ()
    | checkstructure s (r as (Node (Nd { left, right, aabb, ... }))) =
      let
          fun checkpar' which dir NoParent child_aabb =
              raise BDDDynamicTree
                        ("checkstructure " ^ s ^ ": node's " ^
                         which ^ " child's parent is NONE")
            | checkpar' which dir (Parent (p, pdir)) child_aabb =
              if not (BDDCollision.aabb_contains (!aabb, !child_aabb))
              then (print ("AABB\n" ^ s ^ "\n");
                    raise BDDDynamicTree
                             ("checkstructure " ^ s ^ ": node's " ^
                              which ^ " child's aabb is malformed"))
              else if dir = pdir
              then ()
              else (print "L/R\n";
                    raise BDDDynamicTree
                  ("checkstructure " ^ s ^ ": node's " ^
                   which ^ " child's parent is in wrong direction"))

          fun checkpar which dir (Leaf (Lf { parent, aabb, ... })) =
              checkpar' which dir (!parent) aabb
            | checkpar which dir (Node (Nd { parent, aabb, ... })) =
              checkpar' which dir (!parent) aabb

      in
          checkpar "left" Left (!left);
          checkpar "right" Right (!right);
          checkstructure s (!left);
          checkstructure s (!right)
      end

  fun checktreestructure s (ref { node_count : int,
                                  root : 'a tree_node option }) =
      case root of
          NONE => ()
        | SOME tn => checkstructure s tn

  fun checktreestructure _ _ = ()

  fun debugprint pa (tree as ref { node_count, root }) =
      let
          fun indent 0 = ()
            | indent n = (dprint (fn () => " "); indent (n - 1))
          fun pr (depth, Leaf (Lf { data = dat, aabb, parent, ... })) =
              let in
                  indent depth;
                  dprint (fn () => "Leaf: " ^ aabbtos (!aabb) ^ "\n");
                  indent depth;
                  dprint (fn () => " dat: " ^ pa dat ^ "\n");
                  indent depth;
                  case !parent of
                      NoParent => dprint (fn () => "\n")
                    | Parent (_, Left) => dprint (fn () => " dir: Left\n")
                    | Parent (_, Right) => dprint (fn () => " dir: Right\n")
              end
            | pr (depth, Node (Nd { left, right, aabb, parent, ... })) =
              let in
                  indent depth;
                  dprint (fn () => "Node: " ^ aabbtos (!aabb) ^ "\n");
                  indent depth;
                  case !parent of
                      NoParent => dprint (fn () => "\n")
                    | Parent (_, Left) => dprint (fn () => " dir: Left\n")
                    | Parent (_, Right) => dprint (fn () => " dir: Right\n");
                  pr (depth + 2, !left);
                  pr (depth + 2, !right)
              end
      in
          dprint (fn () => "DT: " ^ Int.toString node_count ^ ":\n");
          (case root of
               NONE => ()
             | SOME tn => pr (0, tn));
          checktreestructure "dp" tree
      end


  fun cmp_proxy ((Lf { stamp = a, ... }),
                 (Lf { stamp = b, ... })) = Int.compare (a, b)

  fun eq_proxy p = EQUAL = cmp_proxy p

  local
      val next_stamp_ = ref 0
  in
      fun next_stamp () = (next_stamp_ := !next_stamp_ + 1;
                           !next_stamp_)
  end
  (* Port note: We need to update fields of each object to mimic the
     imperative style of Box2D. We treat the object itself as a ref,
     rather than the updatable fields (the latter would be more
     idiomatic in SML). This allows us to quickly compare the objects
     for equality, but means that we need setter functions for the
     fields that we modify. *)
  fun set_node_count (r as ref { node_count = _, root }, node_count) =
      r := { node_count = node_count, root = root }

  fun set_root (r as ref { node_count, root = _ }, root) =
      r := { node_count = node_count, root = root }

  fun set_parent (Node (Nd {parent, ...}), new_parent) =
      parent := new_parent
    | set_parent (Leaf (Lf {parent, ...}), new_parent) =
      parent := new_parent

  fun set_left (Nd { left, ... }, new_left) =
      left := new_left

  fun set_right (Nd { right, ... }, new_right) =
      right := new_right

  fun get_aabb (Node (Nd {aabb, ...})) = !aabb
    | get_aabb (Leaf (Lf {aabb, ...})) = !aabb

  fun get_parent (Node (Nd {parent, ...})) = !parent
    | get_parent (Leaf (Lf {parent, ...})) = !parent

  fun get_height (Node (Nd {height, ...})) = !height
    | get_height (Leaf _) = 0

  fun set_height (Nd {height, ...}, new_height) = height := new_height

  fun user_data (Lf {data, ... }) = data

  fun fat_aabb (Lf {aabb, ...}) = !aabb

  fun compute_height (ref { root, ... } : 'a dynamic_tree) =
      let fun ch (Leaf _) = 0
            | ch (Node (Nd { left, right, ... })) =
          1 + Int.max(ch (!left), ch (!right))
      in case root of
             NONE => 0
           | SOME tn => ch tn
      end

  fun dynamic_tree () : 'a dynamic_tree =
      ref { node_count = 0, root = NONE }

  fun adjust_height_and_aabb (Nd {aabb, height, left, right, ...}) =
      let in
          aabb := BDDCollision.aabb_combine
                       (get_aabb (!left), get_aabb (!right));
          height := 1 + Int.max (get_height (!left), get_height (!right))
      end

  (* Perform a left or right rotation if node A is imbalanced.
     Returns the new root tree node. *)
  fun balance (_, node as Nd {height = ref 1, ...}) = node
    | balance (tree : 'a dynamic_tree,
               A_interior as Nd {left = ref B, right = ref C, parent = ref A_parent, ...}) =
      let
          val balance = get_height C - get_height B
      in
          if balance > 1
          then (* Rotate C up *)
              let
                  val (F, G, C_interior) = case C of
                                   Node (nd as Nd {left, right, ...}) => (!left, !right, nd)
                                 | Leaf _ => raise BDDDynamicTree "expected Node"
              in
                  (* Swap A and C *)
                  (* Port note: this is a rotation, not a swap. *)
                  set_left (C_interior, Node A_interior);
                  set_parent (C, A_parent);
                  set_parent (Node A_interior, Parent(C_interior, Left));

                  (* A's old parent should point to C *)
                  (case A_parent of
                       Parent (pt, Left) => set_left (pt, C)
                     | Parent (pt, Right) => set_right (pt, C)
                     | NoParent => set_root (tree, SOME C));

                  (* Rotate *)
                  if get_height F > get_height G
                  then
                      (set_right (C_interior, F);
                       set_parent (F, Parent(C_interior, Right));
                       set_right (A_interior, G);
                       set_parent (G, Parent(A_interior, Right))
                      )
                  else
                      (set_right (C_interior, G);
                       set_parent (G, Parent(C_interior, Right));
                       set_right (A_interior, F);
                       set_parent (F, Parent(A_interior, Right))
                      );
                  adjust_height_and_aabb A_interior;
                  adjust_height_and_aabb C_interior;
                  C_interior
              end
          else if balance < ~1
          then (* Rotate B up *)
              let
                  val (D, E, B_interior) = case B of
                                   Node (nd as Nd {left, right, ...}) => (!left, !right, nd)
                                 | Leaf _ => raise BDDDynamicTree "expected Node"
              in
                  (* Swap A and B *)
                  (* Port note: this is a swap, not a rotation. *)
                  set_left (B_interior, Node A_interior);
                  set_parent (B, A_parent);
                  set_parent (Node A_interior, Parent(B_interior, Left));

                  (* A's old parent should point to B *)
                  (case A_parent of
                       Parent (pt, Left) => set_left (pt, B)
                     | Parent (pt, Right) => set_right (pt, B)
                     | NoParent => set_root (tree, SOME B));

                  (* Rotate *)
                  if get_height D > get_height E
                  then
                      (set_right (B_interior, D);
                       set_parent (D, Parent(B_interior, Right));
                       set_left (A_interior, E);
                       set_parent (E, Parent(A_interior, Left))
                      )
                  else
                      (
                       set_right (B_interior, E);
                       set_parent (E, Parent(B_interior, Right));
                       set_left (A_interior, D);
                       set_parent (D, Parent(A_interior, Left))
                      );
                  adjust_height_and_aabb A_interior;
                  adjust_height_and_aabb B_interior;
                  B_interior
              end
          else A_interior
      end

  (* Climb the tree starting at the given node, balancing and keeping
     the AABBS and heights up to date.
     Port note: In the original, usually inlined as a do..while loop.
   *)
  fun climb_and_adjust (tree : 'a dynamic_tree,
                    nd as Nd _) =
      let
          val nd' = balance (tree, nd)
      in
          adjust_height_and_aabb nd';

          case get_parent (Node nd') of
              NoParent => ()
            | Parent (ptn, _) => climb_and_adjust (tree, ptn)
      end

  fun aabb_perimeter {upperbound, lowerbound} =
      let
          val wx = vec2x upperbound - vec2x lowerbound
          val wy = vec2y upperbound - vec2y lowerbound
      in
          2.0 * (wx + wy)
      end

  fun insert_leaf (tree as ref { root, ... } : 'a dynamic_tree,
                   leaf as Lf { aabb = ref leaf_aabb, ... }) =
      (case root of
           NONE =>
               let in
                   (* PERF should always be the case already? *)
                   set_parent (Leaf leaf, NoParent);
                   set_root (tree, SOME (Leaf leaf))
               end
         | SOME tn =>
            (* Find the best sibling for this leaf. *)
            let
                fun find (sibling as (Leaf _)) = sibling
                  | find (sibling as (Node (Nd {aabb, parent, left, right, ...}))) =
                    let
                        val area = aabb_perimeter (!aabb)
                        val combined_aabb = BDDCollision.aabb_combine (!aabb, leaf_aabb)
                        val combined_area = aabb_perimeter combined_aabb
                        (* Cost of creating a new parent for this node and the new leaf *)
                        val cost = 2.0 * combined_area
                        (* Mininum cost of pushing the leaf farther down the tree *)
                        val inheritance_cost = 2.0 * (combined_area - area)

                        fun child_cost (Leaf (Lf {aabb = ref child_aabb, ...})) =
                            inheritance_cost + (aabb_perimeter
                                                    (BDDCollision.aabb_combine
                                                         (leaf_aabb, child_aabb)))
                          | child_cost (Node (Nd {aabb = ref child_aabb, ...})) =
                                let
                                    val aabb = BDDCollision.aabb_combine(leaf_aabb,
                                                                         child_aabb)
                                    val old_area = aabb_perimeter child_aabb
                                    val new_area = aabb_perimeter aabb
                                in
                                    new_area - old_area + inheritance_cost
                                end

                        (* Cost of descending into left child *)
                        val lcost = child_cost (!left)

                        (* Cost of descending into right child *)
                        val rcost = child_cost (!right)

                    in
                      if cost < lcost andalso cost < rcost
                      then sibling
                      else if lcost < rcost
                      then find (!left)
                      else find (!right)
                    end

                val sibling = find tn
                val parent = get_parent sibling
                val new = Nd { parent = ref parent,
                               aabb = ref (BDDCollision.aabb_combine
                                               (leaf_aabb, get_aabb sibling)),
                               (* Port note: Same in both branches. *)
                               left = ref sibling,
                               right = ref (Leaf leaf),
                               height = ref (get_height sibling + 1)}
            in
                set_parent (sibling, Parent (new, Left));
                set_parent (Leaf leaf, Parent (new, Right));

                case parent of
                  NoParent => set_root (tree, SOME (Node new))
                | Parent (nd as Nd {left, right, ...}, dir) =>
                  let
                  in
                      (case dir of
                          Left => left := Node new
                        | Right => right := Node new );

                      climb_and_adjust (tree, nd)
                  end;

                checktreestructure "insert_leaf after" tree
            end)

  fun remove_leaf (tree : 'a dynamic_tree,
                   proxy as Lf {parent, ...}) =
    let
    in
      (* If it's the root, we just make the tree empty. *)
      (case !parent of
          NoParent => set_root (tree, NONE)
        | Parent (Nd { left, right, parent = grandparent, ... }, dir) =>
            let
                (* Get the other child of our parent. *)
                val sibling = case dir of
                                  Left => !right
                                | Right => !left
            in
              case !grandparent of
                  (* Note: discards parent. *)
                  NoParent => (set_parent (sibling, NoParent);
                               set_root (tree, SOME sibling))
                | Parent (gpn as Nd { left = g_left, ... }, dir) =>
                      let
                      in
                          (* Destroy parent and connect grandparent
                             to sibling. *)
                          (case dir of
                               Left => set_left (gpn, sibling)
                             | Right => set_right (gpn, sibling));

                          set_parent (sibling, Parent (gpn, dir));
                          (* Adjust ancestor bounds. *)
                          climb_and_adjust (tree, gpn)
                      end
            end);
       checktreestructure "remove_leaf after" tree
    end

  fun aabb_proxy (tree : 'a dynamic_tree, aabb : aabb, a : 'a) : 'a aabb_proxy =
      let
          fun pxy v =
              Real.fmt (StringCvt.FIX (SOME 2)) (vec2x v) ^ " " ^
              Real.fmt (StringCvt.FIX (SOME 2)) (vec2y v)
          val () = dprint (fn () => "  inc aabb: " ^
                          pxy (#lowerbound aabb) ^ " to " ^
                          pxy (#upperbound aabb) ^ "\n")


          (* Fatten the aabb. *)
          val r : vec2 = vec2(aabb_extension, aabb_extension)
          val fat : aabb = { lowerbound = #lowerbound aabb :-: r,
                             upperbound = #upperbound aabb :+: r }

          val leaf = Lf { aabb = ref fat, data = a, parent = ref NoParent,
                          stamp = next_stamp () }

      in
          set_node_count (tree, #node_count (!tree) + 1);
          insert_leaf (tree, leaf);
          leaf
      end

  fun remove_proxy (tree : 'a dynamic_tree, proxy : 'a aabb_proxy) =
      remove_leaf (tree, proxy)

  fun move_proxy (tree : 'a dynamic_tree,
                  proxy as (Lf { aabb = proxy_aabb,
                                 data, stamp, ... }) : 'a aabb_proxy,
                  aabb : aabb,
                  displacement : vec2) : bool =
      if BDDCollision.aabb_contains (!proxy_aabb, aabb)
      then false
      else
        let
            val () = remove_leaf (tree, proxy)

            (* Predict AABB displacement. *)
            val d : vec2 = aabb_multiplier *: displacement
            val r : vec2 = vec2(aabb_extension, aabb_extension)

            val (blx, bux) = if vec2x d < 0.0
                             then (vec2x d, 0.0)
                             else (0.0, vec2x d)
            val (bly, buy) = if vec2y d < 0.0
                             then (vec2y d, 0.0)
                             else (0.0, vec2y d)

            (* Extend AABB *)
            val b : aabb = { lowerbound =
                               #lowerbound aabb :-: r :+: vec2(blx, bly),
                             upperbound =
                               #upperbound aabb :+: r :+: vec2(bux, buy) }

            fun pxy v =
                Real.fmt (StringCvt.FIX (SOME 2)) (vec2x v) ^ " " ^
                Real.fmt (StringCvt.FIX (SOME 2)) (vec2y v)
            val () = dprint (fn () => "  moved_aabb: " ^
                             pxy (#lowerbound b) ^ " to " ^
                             pxy (#upperbound b) ^ "\n")

        in
            proxy_aabb := b;
            set_parent (Leaf proxy, NoParent);
            insert_leaf (tree, proxy);
            true
        end

  (* Port note: Box2D somewhat strangely uses an explicit stack here
     (might be so that it can abort when the callback returns false
     without using setjmp), which has a maximum depth 128. There's not
     really any reason that the tree can't have an all-left path of
     length greater than 64 (which creates 128 outstanding nodes), at
     which point this function would stop looking at children.
     Rebalancing should prevent that most of the time, but it's better
     to be correct. Implemented instead using an unlimited ML stack
     and exceptions for early exits. *)
  exception Done
  fun query (tree : 'a dynamic_tree,
             f : 'a aabb_proxy -> bool,
             aabb : aabb) : unit =
    let fun q node =
        case node of
            Leaf (leaf as Lf { aabb = leaf_aabb, ... }) =>
            if BDDCollision.aabb_overlap (!leaf_aabb, aabb)
            then if f leaf
                 then ()
                 else raise Done
            else ()
          | Node (Nd { left, right, aabb = node_aabb, ... }) =>
            if BDDCollision.aabb_overlap (!node_aabb, aabb)
            then (q (!left); q (!right))
            else ()
    in case #root (!tree) of
           NONE => ()
         | SOME tn => q tn
    end handle Done => ()

  fun ray_cast (tree : 'a dynamic_tree,
                f : BDDTypes.ray_cast_input * 'a aabb_proxy -> real,
                { p1 : BDDMath.vec2, p2 : BDDMath.vec2,
                  max_fraction : real }) : unit =
    let
      val r0 : vec2 = p2 :-: p1
      val () = if vec2length_squared r0 > 0.0
               then ()
               else raise BDDDynamicTree "ray must have length"
      val r = vec2normalized r0

      (* v is perpendicular to the segment. *)
      val v : vec2 = cross2sv(1.0, r)
      val abs_v : vec2 = vec2abs v


      (* These two are updated in the loop. *)
      val max_fraction = ref max_fraction
      (* Build a bounding box for the segment. *)
      fun make_segment () =
          let val t : vec2 = p1 :+: !max_fraction *: (p2 :-: p1)
          in
              { lowerbound = vec2min(p1, t),
                upperbound = vec2max(p1, t) }
          end
      val segment_aabb : aabb ref = ref (make_segment ())

      (* Port note: Again with the explicit stack. Prevents descent deeper
         than 64 in the worst case. Just use the ML stack and
         exceptions for correctness and simplicity. *)
      fun loop node =
          let
              val node_aabb = get_aabb node
          in
            if not (BDDCollision.aabb_overlap (node_aabb, !segment_aabb))
            then ()
            else
             let
               (* Separating axis for segment (Gino, p80).
                  |dot(v, p1 - c)| > dot(|v|, h) *)
               val c : vec2 = BDDCollision.aabb_center node_aabb
               val h : vec2 = BDDCollision.aabb_extents node_aabb
               val separation : real = Real.abs(dot2(v, p1 :-: c)) - dot2(abs_v, h)
             in
               if separation > 0.0
               then ()
               else
                   case node of
                       Leaf lf =>
                       let
                           val sub_input = { p1 = p1, p2 = p2,
                                             max_fraction = !max_fraction }
                           val value = f (sub_input, lf)
                       in
                           (* Just used as a sentinel for the client to
                              request that the ray cast should stop *)
                           if Real.== (value, 0.0)
                           then raise Done
                           else if value > 0.0
                                then
                                    let in
                                        (* update segment bounding box. *)
                                        max_fraction := value;
                                        segment_aabb := make_segment()
                                    end
                                else ()
                       end
                   | Node (Nd {left, right, ...}) =>
                     (loop (!left); loop (!right))
             end
          end

    in
        case #root (!tree) of
            NONE => ()
          | SOME tn => loop tn
    end handle Done => ()

end
