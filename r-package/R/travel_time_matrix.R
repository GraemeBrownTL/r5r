#' Calculate travel time matrix between origin destination pairs
#'
#' Fast computation of travel time estimates between one or multiple origin
#' destination pairs.
#'
#' @template r5r_core
#' @template common_arguments
#' @template time_window_related_args
#' @template fare_structure
#' @template max_fare
#' @template verbose
#' @param percentiles An integer vector (max length of 5). Specifies the
#'   percentile to use when returning travel time estimates within the given
#'   time window. For example, if the 25th travel time percentile between A and
#'   B is 15 minutes, 25% of all trips taken between these points within the
#'   specified time window are shorter than 15 minutes. Defaults to 50,
#'   returning the median travel time. If a vector with length bigger than 1 is
#'   passed, the output contains an additional column for each percentile
#'   specifying the percentile travel time estimate. each estimate. Due to
#'   upstream restrictions, only 5 percentiles can be specified at a time. For
#'   more details, please see R5 documentation at
#'   'https://docs.conveyal.com/analysis/methodology#accounting-for-variability'.
#'
#' @return A `data.table` with travel time estimates (in minutes) between
#'   origin and destination pairs. Pairs whose trips couldn't be completed
#'   within the maximum travel time and/or whose origin is too far from the
#'   street network are not returned in the `data.table`. If `output_dir` is
#'   not `NULL`, the function returns the path specified in that parameter, in
#'   which the `.csv` files containing the results are saved.
#'
#' @template transport_modes_section
#' @template lts_section
#' @template datetime_parsing_section
#' @template raptor_algorithm_section
#'
#' @family routing
#'
#' @examplesIf identical(tolower(Sys.getenv("NOT_CRAN")), "true")
#' library(r5r)
#'
#' # build transport network
#' data_path <- system.file("extdata/poa", package = "r5r")
#' r5r_core <- setup_r5(data_path)
#'
#' # load origin/destination points
#' points <- read.csv(file.path(data_path, "poa_points_of_interest.csv"))
#'
#' departure_datetime <- as.POSIXct(
#'   "13-05-2019 14:00:00",
#'   format = "%d-%m-%Y %H:%M:%S"
#' )
#'
#' ttm <- travel_time_matrix(
#'   r5r_core,
#'   origins = points,
#'   destinations = points,
#'   mode = c("WALK", "TRANSIT"),
#'   departure_datetime = departure_datetime,
#'   max_trip_duration = 60
#' )
#' head(ttm)
#'
#' # using a larger time window
#' ttm <- travel_time_matrix(
#'   r5r_core,
#'   origins = points,
#'   destinations = points,
#'   mode = c("WALK", "TRANSIT"),
#'   departure_datetime = departure_datetime,
#'   time_window = 30,
#'   max_trip_duration = 60
#' )
#' head(ttm)
#'
#' # selecting different percentiles
#' ttm <- travel_time_matrix(
#'   r5r_core,
#'   origins = points,
#'   destinations = points,
#'   mode = c("WALK", "TRANSIT"),
#'   departure_datetime = departure_datetime,
#'   time_window = 30,
#'   percentiles = c(25, 50, 75),
#'   max_trip_duration = 60
#' )
#' head(ttm)
#'
#' # selecting different percentiles
#' ttm <- travel_time_matrix(
#'   r5r_core,
#'   origins = points,
#'   destinations = points,
#'   mode = c("WALK", "TRANSIT"),
#'   departure_datetime = departure_datetime,
#'   time_window = 30,
#'   percentiles = c(25, 50, 75),
#'   max_trip_duration = 60
#' )
#' head(ttm)
#'
#' # use a fare structure and set a max fare to take monetary constraints into
#' # account
#' fare_structure <- read_fare_structure(
#'   file.path(data_path, "fares/fares_poa.zip")
#' )
#' ttm <- travel_time_matrix(
#'   r5r_core,
#'   origins = points,
#'   destinations = points,
#'   mode = c("WALK", "TRANSIT"),
#'   departure_datetime = departure_datetime,
#'   fare_structure = fare_structure,
#'   max_fare = 5,
#'   max_trip_duration = 60,
#' )
#' head(ttm)
#'
#' stop_r5(r5r_core)
#'
#' @export
travel_time_matrix <- function(r5r_core,
                               origins,
                               destinations,
                               mode = "WALK",
                               mode_egress = "WALK",
                               departure_datetime = Sys.time(),
                               time_window = 1L,
                               percentiles = 50L,
                               fare_structure = NULL,
                               max_fare = Inf,
                               max_walk_dist = Inf,
                               max_bike_dist = Inf,
                               max_trip_duration = 120L,
                               walk_speed = 3.6,
                               bike_speed = 12,
                               max_rides = 3,
                               max_lts = 2,
                               draws_per_minute = 5L,
                               n_threads = Inf,
                               verbose = FALSE,
                               progress = FALSE,
                               output_dir = NULL) {

  old_options <- options(datatable.optimize = Inf)
  on.exit(options(old_options), add = TRUE)

  checkmate::assert_number(n_threads, lower = 1)

  old_dt_threads <- data.table::getDTthreads()
  dt_threads <- ifelse(is.infinite(n_threads), 0, n_threads)
  data.table::setDTthreads(dt_threads)
  on.exit(data.table::setDTthreads(old_dt_threads), add = TRUE)

  # input checking --------------------------------------------------------
  # max_rides, max_lts, verbose, progress and output_dir are checked a bit
  # later when setting r5r_core options

  checkmate::assert_class(r5r_core, "jobjRef")

  origins <- assert_points_input(origins, "origins")
  destinations <- assert_points_input(destinations, "destinations")

  mode_list <- select_mode(mode, mode_egress)

  departure <- posix_to_string(departure_datetime)

  checkmate::assert_number(time_window, lower = 1)
  time_window <- as.integer(time_window)

  checkmate::assert_numeric(
    percentiles,
    lower = 1,
    upper = 99,
    max.len = 5,
    unique = TRUE,
    any.missing = FALSE
  )
  percentiles <- as.integer(percentiles)

  max_walk_time <- set_max_street_time(
    max_walk_dist,
    walk_speed,
    max_trip_duration
  )
  max_bike_time <- set_max_street_time(
    max_bike_dist,
    bike_speed,
    max_trip_duration
  )

  checkmate::assert_number(max_trip_duration, lower = 1)
  max_trip_duration <- as.integer(max_trip_duration)

  checkmate::assert_number(draws_per_minute, lower = 1)
  draws <- time_window * draws_per_minute
  draws <- as.integer(draws)

  # set r5r_core options ----------------------------------------------------

  checkmate::assert_string(output_dir, null.ok = TRUE)
  if (!is.null(output_dir)) {
    checkmate::assert_directory_exists(output_dir)
    r5r_core$setCsvOutput(output_dir)
    on.exit(r5r_core$setCsvOutput(""), add = TRUE)
  }

  # time window
  r5r_core$setTimeWindowSize(time_window)
  r5r_core$setPercentiles(percentiles)
  r5r_core$setNumberOfMonteCarloDraws(draws)

  # travel times breakdown
  r5r_core$setExpandedTravelTimes(FALSE)

  # set bike and walk speed
  set_speed(r5r_core, walk_speed, "walk")
  set_speed(r5r_core, bike_speed, "bike")

  # set max transfers
  set_max_rides(r5r_core, max_rides)

  # set max lts (level of traffic stress)
  set_max_lts(r5r_core, max_lts)

  # set number of threads to be used by r5 and data.table
  set_n_threads(r5r_core, n_threads)

  # set verbose
  set_verbose(r5r_core, verbose)

  # set progress
  set_progress(r5r_core, progress)

  # configure fare structure
  set_fare_structure(r5r_core, fare_structure)

  # set max fare
  # Inf and NULL values are not allowed in Java,
  # so -1 is used to indicate max_fare is unconstrained
  checkmate::assert_numeric(max_fare, lower = 0, len = 1, any.missing = FALSE)
  if (max_fare != Inf) {
    r5r_core$setMaxFare(rJava::.jfloat(max_fare))
  } else {
    r5r_core$setMaxFare(rJava::.jfloat(-1.0))
  }

  # call r5r_core method ----------------------------------------------------

  travel_times <- r5r_core$travelTimeMatrix(origins$id,
                                            origins$lat,
                                            origins$lon,
                                            destinations$id,
                                            destinations$lat,
                                            destinations$lon,
                                            mode_list$direct_modes,
                                            mode_list$transit_mode,
                                            mode_list$access_mode,
                                            mode_list$egress_mode,
                                            departure$date,
                                            departure$time,
                                            max_walk_time,
                                            max_bike_time,
                                            max_trip_duration)


  # process results ---------------------------------------------------------

  # convert travel_times from java object to data.table
  if (!verbose & progress) { cat("Preparing final output...") }

  travel_times <- java_to_dt(travel_times)

  # only perform following operations when result is not empty
  if (nrow(travel_times) > 0) {
    # replace travel-times of nonviable trips with NAs
    #   the first column with travel time information is column 3, because
    #     columns 1 and 2 contain the id's of OD point (hence from = 3)
    #   the percentiles parameter indicates how many travel times columns we'll,
    #     have, with a minimum of 1 (in which case, to = 3).
    for(j in seq(from = 3, to = (length(percentiles) + 2))){
      data.table::set(travel_times, i=which(travel_times[[j]]>max_trip_duration), j=j, value=NA_integer_)
    }
  }

  if (!verbose & progress) { cat(" DONE!\n") }

  if (!is.null(output_dir)) return(output_dir)
  return(travel_times)
}
