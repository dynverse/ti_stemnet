#!/usr/local/bin/Rscript

task <- dyncli::main()

library(jsonlite)
library(readr)
library(dplyr)
library(purrr)
library(tibble)

library(STEMNET)

#   ____________________________________________________________________________
#   Load data                                                               ####


expression <- as.matrix(task$expression)
parameters <- task$parameters
end_id <- task$priors$end_id
groups_id <- task$priors$groups_id

#   ____________________________________________________________________________
#   Infer trajectory                                                        ####

checkpoints <- list(method_afterpreproc = as.numeric(Sys.time()))

# determine end groups
grouping <- groups_id %>% select(cell_id, group_id) %>% deframe() %>% .[rownames(expression)]
end_groups <- grouping[end_id] %>% unique()

# remove end groups with only one cell
end_groups <- intersect(end_groups, names(table(grouping) %>% keep(~. > 2)))

# check if there are two or more end groups
if (length(end_groups) < 2) {
  msg <- paste0("STEMNET requires at least two end cell populations, but according to the prior information there are only ", length(end_groups), " end populations!")

  if (!identical(parameters$force, TRUE)) {
    stop(msg)
  }

  warning(msg, "\nForced to invent some end populations in order to at least generate a trajectory")
  poss_groups <- unique(grouping)
  if (length(poss_groups) == 1) {
    new_end_groups <- stats::kmeans(expression[grouping == poss_groups,], centers = 2)$cluster
    grouping[grouping == poss_groups] <- c(poss_groups, max(grouping) + 1)[new_end_groups]
    end_groups <- new_end_groups
  } else {
    end_groups <- sample(poss_groups, 2)
  }
}

# create stemnet end populations
stemnet_pop <- rep(NA, nrow(expression))
stemnet_pop[which(grouping %in% end_groups)] <- grouping[which(grouping %in% end_groups)]

# run STEMNET
if (parameters$lambda_auto) {parameters$lambda <- NULL}

output <- STEMNET::runSTEMNET(
  expression,
  stemnet_pop,
  alpha = parameters$alpha,
  lambda = parameters$lambda
)

# extract pseudotime and proabilities
pseudotime <- STEMNET:::primingDegree(output)
end_state_probabilities <- output@posteriors %>% as.data.frame() %>% rownames_to_column("cell_id")

#   ____________________________________________________________________________
#   Save output & process output                                            ####

output <- dynwrap::wrap_data(cell_ids = names(pseudotime)) %>%
  dynwrap::add_end_state_probabilities(
    end_state_probabilities = end_state_probabilities,
    pseudotime = pseudotime
  ) %>%
  dynwrap::add_timings(timings = checkpoints)

output %>% dyncli::write_output(task$output)

