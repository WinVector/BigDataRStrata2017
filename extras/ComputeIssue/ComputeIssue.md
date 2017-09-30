ComputeIssue
================

``` r
options(width = 120)
base::date()
```

    ## [1] "Sat Sep 30 08:24:34 2017"

``` r
library(cdata)
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("sparklyr"))
```

    ## Warning: package 'sparklyr' was built under R version 3.4.2

``` r
packageVersion("dplyr")
```

    ## [1] '0.7.4'

``` r
packageVersion("sparklyr")
```

    ## [1] '0.6.3'

``` r
sc <- spark_connect(master = 'local', 
                   version = '2.1.0')
d0 <- copy_to(sc, data.frame(x=1:3, y=6:8), 
              'exampleData')

spark_set_checkpoint_dir(sc, '/Users/johnmount/Documents/work/IHG/ModelProj2/spider/workspace/mountjo/spark-warehouse/zzz')

# trying advice from:
#  https://github.com/rstudio/sparklyr/issues/1026

fRegular <- function(df, si) {
  df %>% 
    mutate(!!si := x+y) %>%
    select(x, y, !!si)
}

fCompute <- function(df, si) {
  df %>% 
    mutate(!!si := x+y) %>%
    select(x, y, !!si) %>%
    compute()
}

fCheckpoint <- function(df, si) {
  df %>% 
    mutate(!!si := x+y) %>%
    select(x, y, !!si) %>%
    compute() %>% sdf_checkpoint()
}

# dies at nsteps=75
# working on  75 fPersist
# Quitting from lines 53-118 (ComputeIssue.Rmd) 
# Error: java.lang.OutOfMemoryError: Java heap space
fPersist <- function(df, si) {
  df %>% 
    mutate(!!si := x+y) %>%
    select(x, y, !!si) %>%
    compute() %>% sdf_persist()
}

timeTheWork <- function(nsteps, d0, f, chain) {
  gc()
  system.time({
    d <- d0
    for(step in seq_len(nsteps)) {
      si <- rlang::sym(paste0('v_', step))
      if(chain) {
        d <- f(d, si)
      } else {
        d <- f(d0, si)
      }
    }
    collect(d) # force calculation
  })
}
```

``` r
fnMap <- 
  list("fRegular"    = fRegular,
      "fCompute"    = fCompute,
      "fCheckpoint" = fCheckpoint,
      "fPersist"    = fPersist)

cutOffs <- 
  c("fRegular"    = 20,
    "fCompute"    = 75,
    "fCheckpoint" = 1000,
    "fPersist"    = 50)

timingDat <- NULL


for(nsteps in c(1, 5, 10, 20, 50, 75, 100)) {
  for(rep in seq_len(3)) {
    for(fname in names(fnMap)) {
      cutoff <- cutOffs[[fname]]
      if((is.null(cutoff)) || (nsteps<=cutoff)) {
        message(paste("working on ", nsteps, fname))
        f <- fnMap[[fname]]
        
        # non-chained d <- f(d0)
        tmnc <- timeTheWork(nsteps, d0, f, FALSE)
        nonChained <- data.frame(seconds = tmnc[[3]],
                                 nstep = nsteps,
                                 fname = fname,
                                 what = 'non_chained',
                                 rep = rep,
                                 stringsAsFactors = FALSE)
        
        # chained d <- f(d)
        tmc <- timeTheWork(nsteps, d0, f, TRUE)
        chained <- data.frame(seconds = tmc[[3]],
                              nstep = nsteps,
                              fname = fname,
                              what = 'chained',
                              rep = rep,
                              stringsAsFactors = FALSE)
        
        timingDat <- bind_rows(timingDat, nonChained, chained)
      }
    }
  }
}
```

``` r
timingDat %>%
  group_by(what, fname, nstep) %>%
  summarize(total_seconds = sum(seconds), total_stages = sum(nstep)) %>%
  mutate(mean_seconds_per_step = total_seconds/total_stages) %>%
  select(-total_seconds, -total_stages) %>%
  cdata::moveValuesToColumns(rowKeyColumns = c('fname', 'nstep'),
                             columnToTakeKeysFrom = 'what', 
                             columnToTakeValuesFrom = 'mean_seconds_per_step') %>%
  rename(chained_seconds_per_step = chained, 
         unchained_seconds_per_step = non_chained) %>% 
  mutate(slowdown = chained_seconds_per_step/unchained_seconds_per_step) %>%
  arrange(fname, nstep) %>%
  as.data.frame()
```

    ##          fname nstep chained_seconds_per_step unchained_seconds_per_step   slowdown
    ## 1  fCheckpoint     1               0.39066667                0.405000000  0.9646091
    ## 2  fCheckpoint     5               0.23953333                0.251200000  0.9535563
    ## 3  fCheckpoint    10               0.24206667                0.216600000  1.1175746
    ## 4  fCheckpoint    20               0.21351667                0.249300000  0.8564648
    ## 5  fCheckpoint    50               0.22872667                0.241413333  0.9474484
    ## 6  fCheckpoint    75               0.39983556                0.350506667  1.1407360
    ## 7  fCheckpoint   100               0.28272333                0.258676667  1.0929603
    ## 8     fCompute     1               0.35166667                0.293666667  1.1975028
    ## 9     fCompute     5               0.17133333                0.160866667  1.0650642
    ## 10    fCompute    10               0.14040000                0.139400000  1.0071736
    ## 11    fCompute    20               0.16125000                0.147200000  1.0954484
    ## 12    fCompute    50               0.21300667                0.147873333  1.4404671
    ## 13    fCompute    75               0.27088444                0.144168889  1.8789383
    ## 14    fPersist     1               0.30766667                0.280000000  1.0988095
    ## 15    fPersist     5               0.19146667                0.189400000  1.0109117
    ## 16    fPersist    10               0.17383333                0.154900000  1.1222294
    ## 17    fPersist    20               0.21275000                0.162516667  1.3090965
    ## 18    fPersist    50               0.26162000                0.153393333  1.7055500
    ## 19    fRegular     1               0.09733333                0.153666667  0.6334056
    ## 20    fRegular     5               0.05160000                0.010466667  4.9299363
    ## 21    fRegular    10               0.08663333                0.006500000 13.3282051
    ## 22    fRegular    20               0.18556667                0.003933333 47.1779661

`compute()` seems to prevent stage dependent slowdown (though it is slow). However, at `n=200` `Java` out of memory exceptions are thrown even with `compute()`.

``` r
timeTheWork(200, d0, fCompute, TRUE)
```

    ## Error: java.lang.OutOfMemoryError: GC overhead limit exceeded
    ##  at scala.collection.mutable.ListBuffer.$plus$eq(ListBuffer.scala:174)
    ##  at scala.collection.mutable.ListBuffer.$plus$eq(ListBuffer.scala:45)
    ##  at scala.collection.TraversableLike$$anonfun$init$1.apply(TraversableLike.scala:457)
    ##  at scala.collection.TraversableLike$$anonfun$init$1.apply(TraversableLike.scala:456)
    ##  at scala.collection.immutable.List.foreach(List.scala:381)
    ##  at scala.collection.TraversableLike$class.init(TraversableLike.scala:456)
    ##  at scala.collection.AbstractTraversable.init(Traversable.scala:104)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:555)
    ##  at org.apache.spark.sql.execution.InputAdapter.generateTreeString(WholeStageCodegenExec.scala:258)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:575)
    ##  at org.apache.spark.sql.execution.WholeStageCodegenExec.generateTreeString(WholeStageCodegenExec.scala:432)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.execution.InputAdapter.generateTreeString(WholeStageCodegenExec.scala:258)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:575)
    ##  at org.apache.spark.sql.execution.WholeStageCodegenExec.generateTreeString(WholeStageCodegenExec.scala:432)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.execution.InputAdapter.generateTreeString(WholeStageCodegenExec.scala:258)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:575)
    ##  at org.apache.spark.sql.execution.WholeStageCodegenExec.generateTreeString(WholeStageCodegenExec.scala:432)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.execution.InputAdapter.generateTreeString(WholeStageCodegenExec.scala:258)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:575)
    ##  at org.apache.spark.sql.execution.WholeStageCodegenExec.generateTreeString(WholeStageCodegenExec.scala:432)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)
    ##  at org.apache.spark.sql.execution.InputAdapter.generateTreeString(WholeStageCodegenExec.scala:258)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:575)
    ##  at org.apache.spark.sql.execution.WholeStageCodegenExec.generateTreeString(WholeStageCodegenExec.scala:432)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.generateTreeString(TreeNode.scala:568)

    ## Timing stopped at: 8.863 0.214 354.4

``` r
spark_disconnect(sc)
```
