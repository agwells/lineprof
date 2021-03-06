#' Line profiling.
#'
#' \code{lineprof} uses R built-in time and memory profiler \code{\link{Rprof}}
#' to collect line profiling data and displays it in ways that help you
#' figure out where the bottlenecks in your code R.
#'
#' R's profiler is a sampling profiler, which means that it stops execution
#' every \code{interval} seconds and records the current call stack. This means
#' that it is somewhat random: if you run the profiler repeatedly on the same
#' code you'll see slightly different outputs depending on exactly where the
#' profiler stopped each time.
#'
#' @section Profiling output:
#'
#' For each sequence of calls, \code{lineprof} calculates:
#'
#' \itemize{
#'   \item \code{time}: the time in seconds
#'   \item \code{alloc}: the memory allocated, in megabytes
#'   \item \code{released}: the memory released, in megabytes. Unless
#'     \code{torture = TRUE} this release is somewhat random:
#'     memory will be only released if a garbage collection is triggered by
#'     an allocation.
#'   \item \code{dups}: the number of calls to the internal \code{duplicate}
#'     function which is called by C code to duplicate R vectors.
#' }
#'
#' Note that memory allocation is only approximate due to the nature of the
#' sampling profiler: if a large block of memory is allocated and then released
#' in between ticks of the timer, no change in memory will be recorded. Using
#' \code{torture = TRUE} helps prevent this, mostly by making R super slow.
#'
#' @section Navigation:
#'
#' There are two ways to navigate through the line profiling output:
#' using a shiny GUI, generated by \code{\link{shine}}; or through the
#' command line, using \code{\link{focus}}.
#'
#' @section Display:
#'
#' The default print method uses \code{reduce_depth} to reduce the call stack
#' to show only two steps down, and then formats the output with
#' \code{format.lineprof}. An alternative option is to use
#' \code{\link{align}}, which when src refs are available, will align the
#' profiling data with the original source code.
#'
#' @param code code to profile.
#' @param interval interval, in seconds, between profile snapshots. R's timer
#'   has a resolution of at best 1 ms, so there's no reason to make this value
#'   smaller, but if you're profiling a long running function you might want to
#'   set it to something larger.
#' @param torture if \code{TRUE}, turns on \code{\link{gctorture}} which forces
#'   \code{\link{gc}} to run after (almost) every allocation. This is useful
#'   if you want to see exactly when memory is released. It also makes R run
#'   extremely slowly (10-100x slower than usual) so it can also be useful to
#'   simulate a smaller \code{interval}.
#' @export
#' @examples
#' source(find_ex("read-delim.r"))
#' source(find_ex("read-table.r")) # local copy so get line numbers
#' wine <- find_ex("wine.csv")
#'
#' \dontrun{
#' x1 <- lineprof(read.table2(wine, sep = ","), torture = TRUE)
#' x2 <- lineprof(read_delim(wine), torture = TRUE)
#'
#' shine(x1)
#' shine(x2)
#' }
#' @useDynLib lineprof
#' @importFrom Rcpp sourceCpp
lineprof <- function(code, interval = 0.001, torture = FALSE) {
  path <- line_profile(code, interval, torture)
  on.exit(unlink(path))

  parse_prof(path)
}

is.lineprof <- function(x) inherits(x, "lineprof")

#' @export
"[.lineprof" <- function(x, ...) {
  out <- NextMethod()
  class(out) <- c("lineprof", "data.frame")
  out
}

paths <- function(x) {
  vapply(x$ref, FUN.VALUE = character(1), function(x) {
    if (length(x$path) == 0) NA_character_ else x$path[[1]]
  })
}

collapse <- function(prof, ignore.path = FALSE) {
  if (ignore.path) {
    # Only needs to compare calls
    call <- vapply(prof$ref, function(x) paste(x$f, collapse = "\u001F"),
      character(1))
    index <- c(FALSE, call[-1] == call[-length(call)])
  } else {
    index <- c(FALSE, unlist(Map(identical, prof$ref[-1], prof$ref[-nrow(prof)])))
  }
  group <- cumsum(!index)

  collapsed <- rowsum(prof[c("time", "alloc", "release", "dups")], group,
    na.rm = TRUE, reorder = FALSE)
  collapsed$ref <- prof$ref[!duplicated(group)]
  class(collapsed) <- c("lineprof", "data.frame")

  collapsed
}
