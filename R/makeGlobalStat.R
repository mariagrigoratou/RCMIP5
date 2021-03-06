
#' Compute global statistic of a variable
#' 
#' Calculates a global summary for CMIP5 data, usually weighted by the 
#' grid cell areas used by each particular model. If no
#' area weighting is supplied, one is computed based on the lon/lat
#' values of \code{x}. The default statistic is \link{weighted.mean},
#' but any summary function that returns a numeric result can be used.
#'
#' @param x A \code{\link{cmip5data}} object
#' @param area An area \code{\link{cmip5data}} object
#' @param verbose logical. Print info as we go?
#' @param sortData logical. Sort \code{x} and \code{area} before computing?
#' @param FUN function. Function to apply across grid
#' @param ... Other arguments passed on to \code{FUN}
#' @return A \code{\link{cmip5data}} object, in which the \code{val} dimensions are the
#' same as the caller for Z (if present) and time, but lon and lat are reduced to 
#' 1 (i.e. no dimensionality). A \code{numCells} field is also added, recording the number
#' of cells in the spatial grid.
#' @details The stat function is calculated for all combinations of lon,
#' lat, and Z (if present).
#' This function is more complicated than the other make...Stat functions, because
#' it provides explicit support for area-weighted functions. We expect that 
#' weighted.mean and a weighted sum will be the most frequent
#' calculations needed. Note that the base R \code{weighted.mean} function doesn't
#' work well for CMIP5 data, and so \code{cmip5.weighted.mean} is used as a default
#' function. Any other user-supplied stat function must 
#' follow the weighted.mean syntax, in particular accepting parameters 'x' 
#' (data) and 'w' (weights) of equal size, as well as dots(...).
#' @note If \code{x} and optional \code{area} are not in the same order, make
#' sure to specify \code{sortData=TRUE}.
#' @seealso \code{\link{makeAnnualStat}} \code{\link{makeZStat}} \code{\link{makeMonthlyStat}} \code{\link{cmip5.weighted.mean}}
#' @examples
#' d <- cmip5data(1970:1975)   # sample data
#' makeGlobalStat(d)
#' summary(makeGlobalStat(d))
#' @export
makeGlobalStat <- function(x, area=NULL, verbose=FALSE, sortData=FALSE, 
                           FUN=cmip5.weighted.mean, ...) {
    
    # Sanity checks
    assert_that(class(x)=="cmip5data")
    assert_that(is.null(area) | class(area)=="cmip5data")
    assert_that(is.flag(verbose))
    assert_that(is.flag(sortData))
    assert_that(is.function(FUN))
    
    # Get and check area data, using 1's if nothing supplied
    areavals <- NA
    if(is.null(area)) {
        if(verbose) cat("No grid areas supplied; using calculated values\n")
        x <- addProvenance(x, "About to compute global stat. Grid areas calculated.")
        if(is.array(x$val)) {
            areavals <- calcGridArea(x$lon, x$lat, verbose=verbose)
        } else {
            areavals <- data.frame(lon=x$lon, lat=x$lat,
                                   value=as.numeric(calcGridArea(x$lon, x$lat, verbose=verbose)))
        }
    } else {
        if(!identical(x$lat, area$lat) & identical(x$lon, area$lon)) {  # must match
            stop("Data and area lon/lat grids differ in dimensionality or area.")
        }
        assert_that(identical(class(area$val), class(x$val)))
        x <- addProvenance(x, "About to compute global stat. Grid areas from following data:")
        x <- addProvenance(x, area)
        areavals <- area$val
        if(is.array(areavals)) {
            dim(areavals) <- dim(areavals)[c(1,2)]
        }
    }
    if(verbose) cat("Area data length", nrow(areavals), "\n")    
    
    # Main computation code
    timer <- system.time({ # time the main computation
        if(is.array(x$val)) {
            myDim <- dim(x$val)
            x$val <- apply(x$val, c(3,4), function(xx,...) {FUN(xx, areavals, ...)}, ...)
            myDim[1:2] <- c(1,1)
            dim(x$val) <- myDim
        } else {
            # Suppress stupid NOTEs from R CMD CHECK
            lon <- lat <- Z <- time <- value <- `.` <- NULL
            
            # The data may be (but hopefully are not) out of order, and if 
            # the user specifies `sortData`, arrange everything so that 
            # area and data order is guaranteed to match. This is expensive, though
            if(sortData) {
                if(verbose) cat("Sorting data...\n")
                areavals <- arrange(areavals, lon, lat)
                x$val <- group_by(x$val, Z, time) %>% 
                    arrange(lon, lat)            
            } else if(missing(sortData) & !missing(area)) {
                warning("Note: 'area' supplied but 'sortData' unspecified; no sorting performed")
            }
            
            # Instead of "summarise(value=FUN(value, ...))", we use the do()
            # call below, because the former doesn't work (as of dplyr 0.3.0.9000):
            # the ellipses cause big problems. This solution thanks to Dennis
            # Murphy on the manipulatr listesrv.        
            if(verbose) cat("Calculating data...\n")
            x$val <- group_by(x$val, Z, time) %>%
                do(data.frame(value = FUN(.$value, areavals$value, ...))) %>%
                ungroup() 
            x$val$lon <- NA
            x$val$lat <- NA
            x[c('lat', 'lon')] <- NULL  
        }
    }) # system.time
    
    if(verbose) cat('Took', timer[3], 's\n')
    
    # Finish up
    x$lat <- NULL
    x$lon <- NULL
    x$numCells <- length(areavals)
    addProvenance(x, paste("Computed", 
                           paste(deparse(substitute(FUN)), collapse="; "),
                           "for lon and lat"))
} # makeGlobalStat
