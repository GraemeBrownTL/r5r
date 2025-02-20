% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{set_n_threads}
\alias{set_n_threads}
\title{Set number of threads}
\usage{
set_n_threads(r5r_core, n_threads)
}
\arguments{
\item{n_threads}{A number.}
}
\value{
No return value, called for side effects.
}
\description{
Sets number of threads to be used by the r5r .jar.
}
\seealso{
Other support functions: 
\code{\link{assert_breakdown_stat}()},
\code{\link{assert_decay_function}()},
\code{\link{assert_points_input}()},
\code{\link{check_connection}()},
\code{\link{fileurl_from_metadata}()},
\code{\link{get_all_od_combinations}()},
\code{\link{posix_to_string}()},
\code{\link{select_mode}()},
\code{\link{set_max_lts}()},
\code{\link{set_max_rides}()},
\code{\link{set_max_street_time}()},
\code{\link{set_progress}()},
\code{\link{set_speed}()},
\code{\link{set_suboptimal_minutes}()},
\code{\link{set_verbose}()},
\code{\link{stop_r5}()}
}
\concept{support functions}
\keyword{internal}
