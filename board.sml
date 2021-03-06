structure Board =
struct
  datatype direction = N | S | E | W
  datatype tile = Cat of direction | Wall | Slime of bool (* active *)
                | Treat
                  (* NB: no "Empty" -- only tiles with stuff are represented *)

  structure IntPairOrd =
  struct
    type ord_key = int * int
    fun compare ((x1, y1), (x2, y2)) =
      if x1 < x2 then LESS
      else if x1 = x2 then
        Int.compare (y1, y2)
        else GREATER
  end

  structure IntPairMap = SplayMapFn (IntPairOrd)

  type board = tile IntPairMap.map
  val empty = IntPairMap.empty
  val insert = IntPairMap.insert'
  val find = IntPairMap.find
  val mapi = IntPairMap.mapi
  val filteri = IntPairMap.filteri
  val numItems = IntPairMap.numItems
  val listItemsi = IntPairMap.listItemsi
  val remove = IntPairMap.remove

  (* Parsing text file representation *)
  fun loadBoard fname =
  let
    val ins = TextIO.openIn fname
    val board = empty
    fun stringToTile s =
      (case s of
            "X" => SOME Wall
          | "%" => SOME Treat
          | "E" => SOME (Cat E)
          | "N" => SOME (Cat N)
          | "S" => SOME (Cat S)
          | "W" => SOME (Cat W)
          | "#" => SOME (Slime false)
          | "*" => SOME (Slime true)
          | _ => NONE)
    fun processLine line =
      let
        val tokens = String.tokens (Char.isSpace) line
      in
        map stringToTile tokens
      end
    (* Add an implicit border along the top, bottom, left, and right edges *)
    fun addBorder (width, height) board =
      let val top = List.tabulate (width, fn x => (x, ~1))
          val bot = List.tabulate (width, fn x => (x, height))
          val lt = List.tabulate (height, fn y => (~1, y))
          val rt = List.tabulate (height, fn y => (width, y))
      in
        foldl
          (fn ((x, y), b) => IntPairMap.insert (b, (x, y), Wall))
          board
          (top @ bot @ lt @ rt)
      end
    fun processLines stream width y board =
      (case (TextIO.inputLine stream) of
           NONE => addBorder (width, y) board
         | SOME line =>
             let
               val tiles = processLine line
               val width = length tiles
               val boardWithAddedLine =
                  ListUtil.foldli
                  (fn (x,tile,b) => 
                      case tile of
                          NONE => b
                        | SOME tile => IntPairMap.insert (b, (x,y), tile)
                  ) board tiles
             in
               processLines stream width (y+1) boardWithAddedLine
             end)
  in
    processLines ins 0 0 board
  end

  fun saveBoard board width height fname =
  let
    val outs = TextIO.openOut fname
    fun tileToString t =
      (case t of
            Wall => "X"
          | Treat => "%"
          | (Cat E) => "E"
          | (Cat W) => "W"
          | (Cat N) => "N"
          | (Cat S) => "S"
          | (Slime true) => "*"
          | (Slime false) => "#")
    fun makeRow y =
      String.concatWith " "
      (List.tabulate (width,
        fn x => (
            case IntPairMap.find (board, (x,y)) of
                 NONE => "."
               | SOME tile => tileToString tile)
        )
      )
    fun writeLines [] = ()
      | writeLines (l::ls) = 
        (TextIO.output (outs, l^"\n"); writeLines ls)
  in
    writeLines
    (List.tabulate (height, fn y => makeRow y));
    TextIO.closeOut outs
  end

end
