## Exploring Social Metacognition
## ACv2 Analysis 
## Matt Jaquiery
## 14 May 2019

## Functions

isSet <- function(v) {
  length(grep(paste0("^", v, "$"), ls(parent.frame())))
}

if (!isSet("studyOffBrandTypeNames")) {
  studyOffBrandTypeNames <- c("disagreeReflected")
}

# libraries ---------------------------------------------------------------

library(testthat) # unit tests
library(curl) # fetching files from server
library(beepr) # beeps for error/complete
library(stringr) # simpler string manipulation
library(forcats) # factor manipulation


# error beeps -------------------------------------------------------------

if (!isSet("silent")) {
  options(error = function() {beep("wilhelm")})
}

# loading functions -------------------------------------------------------

#' Check whether version v is a valid match with test x
#' @param v version string major.minor.patch
#' @param x vector of valid versions or 'all' to match anything
#'  
#' @return boolean
versionMatches <- function(v, x) {
  v <- str_replace_all(v, "-", ".")
  x <- str_replace_all(x, "-", ".")
  
  if ('all' %in% x) {
    T
  } else {
    v %in% x
  }
}

#' List the files on the server matching the specified version
#' @param study to fetch data for. Default for back-compatability
#' @param version version of the experiment to use, or all for all
#' @param rDir remote directory to crawl
listServerFiles <- function(study = "datesStudy", version = "all",
                            rDir = "https://acclab.psy.ox.ac.uk/~mj221/ESM/data/public/" ) {

  out <- NULL
  
  con <- curl(rDir)
  open(con, "rb")
  while (isIncomplete(con)) {
    buffer <- readLines(con, n = 1)
    if (length(buffer)) {
      if (study == "all") {
        f <- reFirstMatch(paste0('([\\w-]*_v[0-9\\-]+_[^"]+.csv)'), buffer)
      } else {
        f <- reFirstMatch(paste0('(', study, '_v[0-9\\-]+_[^"]+.csv)'),
                          buffer)
      }
      
      if (nchar(f)) {
        v <- reFirstMatch(paste0('_v([0-9\\-]+)_[^"]+.csv'), f)
        
        # Check version compatability with version mask
        if (versionMatches(v, version)) {
          out <- c(out, paste0(rDir, f))
        }
      }
    }
  }
  close(con)
  
  out
}

getMarkerList <- function() {
  markersUsed <- c()
  
  # search environment for dataframes
  for (v in ls(.GlobalEnv)) {
    x <- get(v, parent.frame())
    if (is.data.frame(x)) {
      # search data frames for response marker columns
      if ("responseMarkerWidth" %in% names(x)) {
        markersUsed <- c(markersUsed, unique(x$responseMarkerWidth))
      }
      if ("responseMarkerWidthFinal" %in% names(x)) {
        markersUsed <- c(markersUsed, unique(x$responseMarkerWidthFinal))
      }
    }
  }
  
  # output unique values
  unique(markersUsed)
}

# processing functions ----------------------------------------------------

#' Add an additional reason for excluding a participant
#' @param current reason for exclusion
#' @param reason to add to the list
#' @return combined set of reasons
addExclusion <- function(current, reason) {
  if (current == F)
    reason
  else 
    paste(current, reason, collapse = ", ")
}

#' Fix v1.0.0 of minGroups failing to identify advisors
#' @param x dataframe to adjust
fixGroups <- function(x) {
  if ((studyName == "minGroups" && "1-0-0" %in% studyVersion)
      | (studyName == "directBenevolence" && "1-2-0" %in% studyVersion)) {
    
    advisorDescription <- function(id, condition) {
      if (id == 1) {
        if (condition %% 2 == 1)
          "inGroup"
        else 
          "outGroup"
      } else {
        if (condition %% 2 == 1)
          "outGroup"
        else
          "inGroup"
      }
    }
    
    vars <- grep("idDescription", names(x), value = T)
    for (v in vars) {
      
      id <- sub("Description", "", v)
    
      # Prepare factor levels
      if (!("inGroup" %in% levels(x[[v]]))) {
        levels(x[[v]]) <- c(levels(x[[v]]), "inGroup", "outGroup")
      }
      
      # Fix table
      for (i in which(x[[v]] == "Unset")) {
        x[i, v] <- 
          advisorDescription(x[i, id], 
                             okayIds$condition[okayIds$pid %in% x$pid[i]])
      }
      
      x[[v]] <- factor(x[[v]])
    }
  }
  
  x
}

#' Extract a list of advisor names and ids from a data frame where advisors are
#' sequentially numbered
#' @param x dataframe
getAdvisorDetails <- function(x) {
  
  names <- NULL
  types <- NULL
  i <- 0
  maxAdvisors <- 100
  
  while (T && i < maxAdvisors) {
    if (!length(grep(paste0("advisor", i), names(x)))) {
      break()
    }
    names <- unique(c(names, 
                      unique(x[, paste0("advisor", i, 
                                        "idDescription")])))
    
    types <- unique(c(types, 
                      unique(x[, paste0("advisor", i, 
                                        "actualType")]),
                      unique(x[, paste0("advisor", i, 
                                        "nominalType")])))
    i <- i + 1
  }
  
  types <- unlist(types)
  types <- types[nchar(types) > 0]
  
  list(
    names = unlist(names),
    types = types
  )
}

#' Calculate variables detailing the quality of a response
#' @param ca correct answer
#' @param elb estimate lower bound
#' @param ew estimate width
#' @param mv estimate marker value
#' @param cas correct answer side
#' @param ra response answer (side)
#' @param rc response confidence
#' @param suffix to append to each variable name
#'
#' The first 4 variables are used in the timeline response tasks, the ra and
#' rc variables are used for the binary response scale.
#'
#' @return data frame with columns for response correctness, error, and score
getResponseVars <- function(ca, elb, ew, mv, cas, ra, rc, suffix = NULL) {
  # Detect the correct mode to be in
  if (!is.null(cas) && !is.null(ra) && !is.null(rc))
    return(getResponseVars.binary(cas, ra, rc, suffix = suffix))
  
  if (is.null(mv)) {
    mv <- 27 / ew
  }
  
  n <- length(ca)
  
  if (length(elb) != n || length(ew) != n) {
    stop("Lengths of all input vectors must be the same.")
  }
  
  x <- data.frame(
    responseCorrect = ca >= elb & ca <= elb + ew,
    responseError = abs(ca - elb + (ew / 2))
  )
  
  x$responseScore <- ifelse(x$responseCorrect, mv, 0)
  
  if (!is.null(suffix)) {
    names(x) <- paste0(names(x), suffix)
  }
  
  x
}

#' Binary case for \code{getResponseVars()}
getResponseVars.binary <- function(cas, ra, rc, suffix = NULL) {
  n <- length(cas)
  
  if (length(ra) != n || length(rc) != n) {
    stop("Lengths of all input vectors must be the same.")
  }
  
  x <- data.frame(
    responseCorrect = cas == ra,
    responseError = ifelse(cas == ra, 100 - rc, 100 + rc),
    responseScore = ifelse(cas == ra, rc, -rc)
  )
  
  if (!is.null(suffix)) {
    names(x) <- paste0(names(x), suffix)
  }
  
  x
}

#' Calculate the derived variables for a dataframe
#' @param df data frame to calculate derived variables for
#' @param name of the dataframe extracted from its csv file
#' @param opts list of options for calculating variables
#' 
#' @return df with derived variables in new columns
getDerivedVariables <- function(x, name, opts = list()) {
  
  if (!nrow(x))
    return(x)
  
  switch(
    name,
    
    # ADVISORS ----------------------------------------------------------------
    
    advisors = {
      fixGroups(x)
    },
    
    # ADVISED TRIAL -----------------------------------------------------------
    
    AdvisedTrial = {
      if (!is.null(opts$skipMixedOffsets) && length(opts$skipMixedOffsets) &&
          opts$skipMixedOffsets && is.factor(x$correctAnswer)) {
        # Remove rows in broken files where the correct answer field isn't a
        # number
        x <- x[which(!is.na(as.numeric(as.character(x$correctAnswer)))), ]
        x$correctAnswer <- as.numeric(as.character(x$correctAnswer))
      }
      
      x <- fixGroups(x)
      
      details <- getAdvisorDetails(x)
      advisorNames <- details[["names"]]
      
      # trial variables ---------------------------------------------------------
      
      # Check trials which are supposed to have feedback actually have it
      if (!("feedback" %in% names(x))) {
        x$feedback <- !is.na(x$timeFeedbackOn)
      }
      
      x$feedback[is.na(x$feedback)] <- 0
      x$feedback <- as.logical(x$feedback)
      
      if (is.null(opts$skipFeedbackCheck) || !opts$skipFeedbackCheck)  {
        expect_equal(!is.na(x$timeFeedbackOn), x$feedback)
      }
      
      x <- cbind(x, getResponseVars(x$correctAnswer,
                                    x$responseEstimateLeft,
                                    x$responseMarkerWidth,
                                    x$responseMarkerValue,
                                    x$correctAnswerSide,
                                    x$responseAnswerSide,
                                    x$responseConfidence))
      
      x <- cbind(x, getResponseVars(x$correctAnswer,
                                    x$responseEstimateLeftFinal,
                                    x$responseMarkerWidthFinal,
                                    x$responseMarkerValueFinal,
                                    x$correctAnswerSide,
                                    x$responseAnswerSideFinal,
                                    x$responseConfidenceFinal,
                                    suffix = "Final"))
      
      x <- as.tibble(x)
      
      x$errorReduction <- x$responseError - 
        x$responseErrorFinal
      
      x$responseScore <- 
        ifelse(x$responseCorrect, 27 / x$responseMarkerWidth, 0)
      
      x$responseScoreFinal <- 
        ifelse(x$responseCorrectFinal, 27 / x$responseMarkerWidthFinal, 0)
      
      x$accuracyChange <- x$responseCorrectFinal - x$responseCorrect
      
      x$scoreChange <- x$responseScoreFinal - x$responseScore
      
      if ("responseEstimateLeft" %in% names(x)) {
        x$estimateLeftChange <- abs(x$responseEstimateLeftFinal -
                                      x$responseEstimateLeft)
        x$changed <- x$estimateLeftChange > 0
      
        x$confidenceChange <- 
          (4 - as.numeric(x$responseMarkerFinal)) -
          (4 - as.numeric(x$responseMarker))
      }
      if (!is.null(x$responseConfidence)) {
        x$confidenceChange <- 
          ifelse(x$responseAnswerSide == x$responseAnswerSideFinal,
                 x$responseConfidenceFinal - x$responseConfidence,
                 x$responseConfidenceFinal + x$responseConfidence)
        x$changed <- x$confidenceChange != 0
      }
      
      
      tmp <- x[order(x$number), ]
      
      x$firstAdvisor <- unlist(sapply(x$pid, 
                                      function(id) 
                                        tmp[tmp$pid == id,
                                            "advisor0idDescription"][1, ]))
      
      x$advisor0offBrand <- x$advisor0actualType %in% studyOffBrandTypeNames
      
      
      # by advisor name variables -----------------------------------------------
      
      # Produce equivalents of the advisor1|2... variables which are named for the 
      # advisor giving the advice
      
      # Find the index for each advisor
      for (a in advisorNames) {
        x[[paste0(a, '.index')]] <- unlist(
          sapply(1:nrow(x), function(i) {
            tmp <- x[i, grepl('^advisor[0-0]+idDescription$', names(x))]
            tmp <- t(tmp)
            rn <- rownames(tmp)[tmp[1] == a]
            if (length(rn) != 1)
              NA
            else
              reFirstMatch('advisor([0-9]+)idDescription', rn)
          })
          )
      }
      
      # Use the index to patch in the advisor's value
      for (v in names(x)[grepl("advisor0", names(x))]) {
        suffix <- reFirstMatch("advisor0(\\S+)", v)
        
        f <- is.factor(x[[paste0('advisor0', suffix)]])
        
        for (a in advisorNames) {
          
          s <- paste0(a, ".", suffix)
          x[[s]] <- unlist(
            sapply(1:nrow(x), function(i) {
              index <- x[i, paste0(a, '.index')]
              if (is.na(index))
                NA
              else {
                tmp <- x[i, paste0('advisor', index, suffix)]
                if (f) 
                  as.character(tmp)
                else
                  tmp
              }
            })
            )
          
          if (f) {
            x[[s]] <- patchFactor(x[[s]], x[[paste0('advisor0', suffix)]])
          }
        }
      }
      
      # Trials - advisor-specific variables
      for (a in advisorNames) {
        
        # Weight on Advice
        if ("responseEstimateLeft" %in% names(x)) {
          # Accuracy
          x[, paste0(a, ".accurate")] <- 
            (x[, paste0(a, ".advice")] - 
               (x[, paste0(a, ".adviceWidth")] / 2)) <= x[, "correctAnswer"] &
            (x[, paste0(a, ".advice")] + 
               (x[, paste0(a, ".adviceWidth")] / 2)) >= x[, "correctAnswer"]
          
          # Error
          x[, paste0(a, ".error")] <- 
            abs(x[, paste0(a, ".advice")] - x[, "correctAnswer"])
          i <- x[, "responseEstimateLeft"] + (x[, "responseMarkerWidth"] - 1) / 2
          f <- x[, "responseEstimateLeftFinal"] + 
            (x[, "responseMarkerWidthFinal"] - 1) / 2
          adv <- x[, paste0(a, ".advice")]
          
          z <- ((f - i) / (adv - i))
          x[, paste0(a, ".woaRaw")] <- z
          
          z[z < 0] <- 0
          z[z > 1] <- 1
          
          x[, paste0(a, ".woa")] <- z
          
          for (d in c("", "Final")) {
            minA <- x[, paste0(a, ".advice")] - 
              (x[, paste0(a, ".adviceWidth")] / 2)
            maxA <- x[, paste0(a, ".advice")] + 
              (x[, paste0(a, ".adviceWidth")] / 2)
            
            # Timeline responses
            if ("responseEstimateLeft" %in% names(x)) {
              minP <- x[, paste0("responseEstimateLeft", d)]
              maxP <- minP + x[, paste0("responseMarkerWidth", d)]
              
              x[, paste0(a, ".agree", d)] <- 
                ((minA >= minP) & (minA <= maxP)) | ((maxA >= minP) & (maxA <= minP)) 
              
              # Distance
              reMid <- minP + (maxP - minP) / 2
              adv <- x[, paste0(a, ".advice")]
              x[, paste0(a, ".distance", d)] <- abs(reMid - adv)
            } 
          }
        }
        if ("responseAnswerSide" %in% names(x)) {
          aa <- x[, paste0(a, ".adviceSide")]
          ac <- x[, paste0(a, ".adviceConfidence")]
          pa <- x$responseAnswerSide
          paf <- x$responseAnswerSideFinal
          pc <- x$responseConfidence
          pcf <- x$responseConfidenceFinal
          
          # Accuracy
          x[, paste0(a, ".accurate")] <- aa == x$correctAnswerSide
          
          # Error
          x[, paste0(a, ".error")] <- ifelse(aa == x$correctAnswerSide,
                                             pull(100 - ac), 
                                             pull(100 + ac))
          
          # Influence
          influence <- ifelse(pa == paf, # amount original answer reinforced
                              pcf - pc, 
                              pcf + pc)
          # inverse if disagreeing
          m <- as.logical(!is.na(aa != paf) & aa != paf)
          influence[m] <- -influence[m]
          x[, paste0(a, ".influence")] <- influence
          
          for (d in c("", "Final")) {
            if (d == "Final") {
              p <- paf
              conf <- pcf
            } else {
              p <- pa
              conf <- pc
            }

            x[, paste0(a, ".agree", d)] <- aa == p
            
            x[, paste0(a, ".distance", d)] <- ifelse(aa == p,
                                                     pull(abs(conf - ac)), 
                                                     pull(conf + ac))
          }
        }
        
        # Agreement change
        x[, paste0(a, ".agreementChange")] <- 
          x[, paste0(a, ".agreeFinal")] - 
          x[, paste0(a, ".agree")]
      }
      
      # backfilling advisor0 properties -----------------------------------------
      
      if (paste0(as.character(x$advisor0idDescription[1]), ".woa") 
          %in% 
          names(x)) {
        x$woa <- NA
        
        low <- 0
        high <- 1
        n <- 11
        
        for (z in c("woa", "woaRaw")) {
          x[, paste0("advisor0", z)] <- 
            sapply(1:nrow(x), function(i)
              unlist(
                x[i, paste0(as.character(x$advisor0idDescription[i]), ".", z)]))
        }
        
        x$woa[x$advisor0woaRaw >= 1] <- ">=1"
        for (z in rev(seq(low, high, length.out = n))) {
          x$woa[x$advisor0woaRaw < z] <- paste0("<", z)
        }
        x$woa <- factor(x$woa)
      }
      
      x
    },
    
    # Process withconf trials in the same way as above
    AdvisedTrialWithConf = {
      getDerivedVariables(x, name = "AdvisedTrial", opts = opts)
    },
    
    # TRIAL -------------------------------------------------------------------
    
    Trial = {
      
      x <- cbind(x, getResponseVars(x$correctAnswer,
                                    x$responseEstimateLeft,
                                    x$responseMarkerWidth,
                                    x$responseMarkerValue,
                                    x$correctAnswerSide,
                                    x$responseAnswerSide,
                                    x$responseConfidence))
      
      as.tibble(x)
    },
    
    x
  )
}


# wrangling functions -----------------------------------------------------

#' strip newlines and html tags from string
stripTags <- function(s) {
  s <- gsub("[\r\n]", "", s)
  
  while (any(grepl("  ", s, fixed = T)))
    s <- gsub("  ", " ", s, fixed = T)
  
  s <- gsub("^ ", "", s, perl = T)
  s <- gsub(" $", "", s, perl = T)
  
  while (any(grepl("<([^\\s>]+)[^>]*>([\\s\\S]*?)<\\/\\1>", s, perl = T)))
    s <- gsub("<([^\\s>]+)[^>]*>([\\s\\S]*?)<\\/\\1>", "\\2", s, perl = T)
  
  s <- gsub("<[^>]+\\/>", "", s)
  s
}

#' extract only numbers from a string as one number
#' @param s string
#' 
#' @return numeric representation of the result
numerify <- function(s) {
  as.numeric(gsub("[^0-9\\.]", "", s))
}

#' Return the first match for a regexpr
reFirstMatch <- function(pattern, str, ...) {
  re <- regexpr(pattern, str, ..., perl = T)
  name <- substr(str, attr(re, "capture.start"), 
                 attr(re, "capture.start") + attr(re, "capture.length") - 1)
  name
}

expect_equal(reFirstMatch("\\w+\\W+(\\w+)", "First, Second, Third"), "Second")

#' rbind with NA padding for missing columns
#' @params x list of data frames to join
#' @params padWith value for missing entries
safeBind <- function(x, padWith = NA) {
  
  out <- NULL
  first <- T
  
  pad <- function(a, b) {
    missing <- names(b)[names(b) %in% names(a) == F]
    
    for (v in missing) {
      if (nrow(a)) {
        a[, v] <- padWith
      } else {
        a[, v] <- do.call(typeof(b[, v]), args = list())
      }
    }
    
    a
  }
  
  for (y in x) {
    
    if (!is.data.frame(y))
      y <- as.data.frame(y)
    
    if (first) {
      out <- y
      first <- F
    } else {
      y <- pad(y, out)
      out <- pad(out, y)
      out <- rbind(out, y)
    }
  }
  
  out
}

expect_equal(dim(safeBind(list(data.frame(x = 1:5, y = runif(5), rnorm(5)),
                               data.frame(x = 6:10, z = 1:5)))),
             c(10, 4))

#' Return a factor safely inheriting specified level labels
#' @param x vector to factorize
#' @param y factor whose levels x should inherit
#' @param dropUnused whether to drop levels of y not in use by y
#' @param ... additional arguments to try to pass to \code{factor()}
#' @return x as a factor with y's labels 
patchFactor <- function(x, y, dropUnused = T, ...) {
  z <- c(x, unique(y))
  if (dropUnused)
    z <- factor(z, labels = levels(factor(y)), ...)
  else
    z <- factor(z, labels = levels(y), ...)
  z[1:length(x)]
}

#' List the unique values of a vector and a "total" item with all unique values
#' Designed for outputting aggregate counts and totals
uniqueTotal <- function(x) {
  out <- as.list(unique(x))
  out[[length(out) + 1]] <- unique(x)
  out
}

expect_equal(uniqueTotal(c("a", "b", "c")), 
             list("a", "b", "c", c("a", "b", "c")))

#' Return a version of df with only the trials with a single advisor, 
#' and with all advice columns accessible as advisor0x where x is the 
#' name of the advisor column.
#' @param df data frame to process
singleAdvisorTrials <- function(df) {
  
  details <- getAdvisorDetails(x)
  advisorNames <- details[["names"]]
  
  # Find the number of advisors by counting advisorXadvice columns
  df$advisorCount <- 0
  for (r in 1:nrow(df)) {
    i <- 0
    while (T) {
      if (!length(grep(paste0("advisor", i), names(df)))) {
        break()
      }
      
      i <- i + 1
    }
    df$advisorCount[r] <- i
  }
  
  # Only keep trials with a single advisor
  out <- df[df$advisorCount == 1, ]
  
  # fill in missing column names using the advisor's description + varname
  advCols <- unique(reFirstMatch(paste0("(?:",
                                        paste(advisorNames, collapse = "|"),
                                        ")\\.(\\S+)$"), names(df)))
  advCols <- advCols[!(advCols %in% unique(reFirstMatch("advisor0(\\S+)$", 
                                                        names(df))))]
  for (i in 1:nrow(out)) {
    for (v in advCols) {
      out[i, paste0("advisor0", v)] <- 
        out[i, paste0(out$advisor0idDescription[i], ".", v)]
    }
  }
  
  out
}

#' Produce a data frame of the trials where each decision gets a unique row
#' @param df trials with initial and final decisions
#' @return copy of df with a row per decision rather than per trial
byDecision <- function(df) {
  out <- df[, !grepl("^response(?=\\S+Final$)", names(df), perl = T)]
  
  out <- rbind(out, out)
  
  n <- nrow(df)
  
  out$decision <- sapply(1:nrow(out), 
                               function(x) 
                                 if (x <= n) "first" else "last")
  
  for (i in (n + 1):nrow(out)) {
    
    # fill in final responses in the initial response columns for final decisions
    for (v in names(out)[grepl("^response", names(out), perl = T)]) {
      old <- out[[v]][i]
      new <- df[[paste0(v, "Final")]][i - n]
      
      if (is.factor(old)) {
        if (!(new %in% levels(old))) {
          out[[v]] <- fct_expand(out[[v]], levels(new))
        }
      } 
      out[[v]][i] <- new
    }
  }
  
  out
}

#' Extract participant summary variables
#' @param df trials to process
#' @param extract vector of numeric variables to extract (NULL for default)
#' @param by vector of categorical variables to aggregate by
#' @return table of participant summary stats
participantSummary <- function(df, extract = NULL, by = NULL) {
  
  if ("studyVersion" %in% names(df) && length(unique(df$studyVersion)) > 1) {
    # Calculate summary separately for each version
    out <- NULL
    
    for (v in unique(df$studyVersion)) {
      tmp <- df[df$studyVersion == v, ]
      out <- safeBind(list(out, participantSummary(tmp, extract, by)))
    }
    
    return(out)
  }
  
  if (is.null(extract))
    extract <- c("timeEnd", "responseCorrect", "responseError", "number")
  if (is.null(by))
    by <- c("pid", "responseMarker", "feedback", "decision")
  
  eq <- paste0("cbind(", paste(extract, collapse = ", "), ") ~ ", 
               paste(by, collapse = " + "))
  
  PP <- as.tibble(aggregate(as.formula(eq), df, mean))
  
  # record the n of each row so weighted averaging can be used later
  PP$number <- aggregate(as.formula(paste("number ~", 
                                          paste(by, collapse = " +"))), 
                         df, length)$number
  
  # Calculate the proportion of trials each breakdown in PP accounts for
  PP$proportion <- sapply(1:nrow(PP), 
                          function(i) 
                            length(unique(PP$decision)) * PP$number[i] / 
                            sum(PP$number[PP$pid == PP$pid[i]]))
  
  # Pad out the proportions with 0s
  for (p in unique(PP$pid)) {
    for (d in unique(PP$decision))
      for (m in unique(df$responseMarker))
        if (nrow(PP[PP$pid == p & 
                    PP$decision == d &
                    PP$responseMarker == m, ]) == 0)
          PP <- safeBind(list(PP, 
                              tibble(pid = p,
                                     responseMarker = m,
                                     feedback = PP$feedback[PP$pid == p][1],
                                     decision = d,
                                     number = 0,
                                     proportion = 0)))
  }
  
  PP
}

# analysis functions ------------------------------------------------------

#' Means of v for each marker after converting df entries to participant means
#' @param v column
#' @param df dataframe containing v
#' @param hideTotals whether to hide total rows
#' @param hideMarkerTotal whether to hide total column for markers
#' @param missingValue which value to use where values are missing
#' @param ... passed on to mean
markerBreakdown <- function(v, 
                            df, 
                            hideTotals = F,
                            hideMarkerTotal = F, 
                            missingValue = NA,
                            ...) {
  v <- substitute(v)
  
  markers <- getMarkerList()
  markerList <- markers[markers %in% df$responseMarker]
  
  fun <- function(x) {
    if (!nrow(x))
      return(missingValue)
    eq <- as.formula(paste(ensym(v), "~ + pid"))
    tmp <- aggregate(eq, x, mean, ...)
    mean(tmp[, ncol(tmp)])
  }
  
  u <- if (hideTotals) unique else uniqueTotal # function for unique values
  
  # rename total fields
  n <- function(x, alt = NA) if (length(x) == 1) x else alt
  
  out <- list()
  for (d in u(df$decision)) {
    if (length(d) != 1)
      next()
    
    for (f in u(df$feedback)) {
      tmp <- tibble(decision = n(d), feedback = n(f))
      
      for (m in u(markerList)) {
        if (length(m) != 1 && hideMarkerTotal)
          next()
        
        x <- fun(df[df$decision %in% d & 
                      df$feedback %in% f &
                      df$responseMarker %in% m, ])
        
        if (is.na(n(m)))
          tmp$mean <- x
        else
          tmp[paste0("mean|m=", m)] <- x
      }
      
      out[[d]] <- rbind(out[[d]], tmp)
    }
  }
  
  out
}

#' Output of a function (usually mean_cl_*) applied to participant means.
#' Results shown for first and last decisions, as well as a total.
#'
#' tbl should probably be decisions dataframe, and columns pid and decision are
#' expected to exist
#'
#' @param tbl tibble with data
#' @param colName column to apply the function to
#' @param groupCol column to use for grouping
#' @param idCol participant identifier column
#' @param f function to run
#' @param ... passed on to f
peek <- function(tbl, colName, groupCol, 
                 idCol = as.symbol("pid"), f = mean_cl_normal, ...) {
  v <- substitute(colName)
  g <- substitute(groupCol)
  
  byD <- tbl %>% group_by(!!idCol, !!g) %>%
    summarise(x = mean(!!v)) %>%
    group_by(!!g) %>%
    do(x = f(.$x, ...)) %>%
    unnest(x) 
  
  allDF <- tbl %>% group_by(!!idCol) %>%
    summarise(x = mean(!!v)) %>%
    do(x = f(.$x, ...)) %>%
    unnest(x)
  
  allDF <- tibble(decision = "Overall") %>% cbind(allDF)
  
  rbind(byD, allDF)
  
} 

#' Number of points a marker is worth
#' @param width of the marker
#' @return points the marker is worth
markerPoints <- function(width) 27 / width
