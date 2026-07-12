# Signature registry loader + condition evaluator for the Slope Prospector.
library(yaml)

load_signatures <- function(path) {
  raw <- yaml.load_file(path)
  raw$signatures
}
