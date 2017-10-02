ComputeIssue
================

``` r
options(width = 120)
base::date()
```

    ## [1] "Mon Oct  2 05:55:40 2017"

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
    ## 1  fCheckpoint     1               0.40033333                0.424666667  0.9427002
    ## 2  fCheckpoint     5               0.25840000                0.279133333  0.9257225
    ## 3  fCheckpoint    10               0.24800000                0.252333333  0.9828269
    ## 4  fCheckpoint    20               0.23110000                0.260266667  0.8879355
    ## 5  fCheckpoint    50               0.22464000                0.254660000  0.8821173
    ## 6  fCheckpoint    75               0.46513333                0.358426667  1.2977085
    ## 7  fCheckpoint   100               0.29073667                0.255883333  1.1362079
    ## 8     fCompute     1               0.38066667                0.315666667  1.2059134
    ## 9     fCompute     5               0.18306667                0.178933333  1.0230999
    ## 10    fCompute    10               0.15426667                0.142233333  1.0846028
    ## 11    fCompute    20               0.18538333                0.170583333  1.0867611
    ## 12    fCompute    50               0.21627333                0.155273333  1.3928556
    ## 13    fCompute    75               0.27840889                0.149511111  1.8621284
    ## 14    fPersist     1               0.30400000                0.298666667  1.0178571
    ## 15    fPersist     5               0.19253333                0.190733333  1.0094373
    ## 16    fPersist    10               0.18113333                0.171566667  1.0557606
    ## 17    fPersist    20               0.21621667                0.193750000  1.1159570
    ## 18    fPersist    50               0.27806000                0.149600000  1.8586898
    ## 19    fRegular     1               0.10933333                0.164666667  0.6639676
    ## 20    fRegular     5               0.05700000                0.010533333  5.4113924
    ## 21    fRegular    10               0.09073333                0.006600000 13.7474747
    ## 22    fRegular    20               0.25630000                0.006383333 40.1514360

`compute()` seems to prevent stage dependent slowdown (though it is slow). However, at `n=200` `Java` out of memory exceptions are thrown even with `compute()`.

``` r
timeTheWork(200, d0, fCompute, TRUE)
```

    ## Error: java.lang.OutOfMemoryError: GC overhead limit exceeded
    ##  at java.util.Arrays.copyOfRange(Arrays.java:3664)
    ##  at java.lang.String.<init>(String.java:207)
    ##  at java.lang.StringBuilder.toString(StringBuilder.java:407)
    ##  at scala.collection.mutable.StringBuilder.toString(StringBuilder.scala:430)
    ##  at org.apache.spark.sql.catalyst.trees.TreeNode.treeString(TreeNode.scala:487)
    ##  at org.apache.spark.sql.execution.QueryExecution$$anonfun$toString$3.apply(QueryExecution.scala:232)
    ##  at org.apache.spark.sql.execution.QueryExecution$$anonfun$toString$3.apply(QueryExecution.scala:232)
    ##  at org.apache.spark.sql.execution.QueryExecution.stringOrError(QueryExecution.scala:107)
    ##  at org.apache.spark.sql.execution.QueryExecution.toString(QueryExecution.scala:232)
    ##  at org.apache.spark.sql.execution.SQLExecution$.withNewExecutionId(SQLExecution.scala:54)
    ##  at org.apache.spark.sql.Dataset.withNewExecutionId(Dataset.scala:2765)
    ##  at org.apache.spark.sql.Dataset.org$apache$spark$sql$Dataset$$execute$1(Dataset.scala:2370)
    ##  at org.apache.spark.sql.Dataset.org$apache$spark$sql$Dataset$$collect(Dataset.scala:2377)
    ##  at org.apache.spark.sql.Dataset$$anonfun$count$1.apply(Dataset.scala:2405)
    ##  at org.apache.spark.sql.Dataset$$anonfun$count$1.apply(Dataset.scala:2404)
    ##  at org.apache.spark.sql.Dataset.withCallback(Dataset.scala:2778)
    ##  at org.apache.spark.sql.Dataset.count(Dataset.scala:2404)
    ##  at org.apache.spark.sql.execution.command.CacheTableCommand.run(cache.scala:45)
    ##  at org.apache.spark.sql.execution.command.ExecutedCommandExec.sideEffectResult$lzycompute(commands.scala:58)
    ##  at org.apache.spark.sql.execution.command.ExecutedCommandExec.sideEffectResult(commands.scala:56)
    ##  at org.apache.spark.sql.execution.command.ExecutedCommandExec.doExecute(commands.scala:74)
    ##  at org.apache.spark.sql.execution.SparkPlan$$anonfun$execute$1.apply(SparkPlan.scala:114)
    ##  at org.apache.spark.sql.execution.SparkPlan$$anonfun$execute$1.apply(SparkPlan.scala:114)
    ##  at org.apache.spark.sql.execution.SparkPlan$$anonfun$executeQuery$1.apply(SparkPlan.scala:135)
    ##  at org.apache.spark.rdd.RDDOperationScope$.withScope(RDDOperationScope.scala:151)
    ##  at org.apache.spark.sql.execution.SparkPlan.executeQuery(SparkPlan.scala:132)
    ##  at org.apache.spark.sql.execution.SparkPlan.execute(SparkPlan.scala:113)
    ##  at org.apache.spark.sql.execution.QueryExecution.toRdd$lzycompute(QueryExecution.scala:87)
    ##  at org.apache.spark.sql.execution.QueryExecution.toRdd(QueryExecution.scala:87)
    ##  at org.apache.spark.sql.Dataset.<init>(Dataset.scala:185)
    ##  at org.apache.spark.sql.Dataset$.ofRows(Dataset.scala:64)
    ##  at org.apache.spark.sql.SparkSession.sql(SparkSession.scala:592)

    ## Timing stopped at: 11.32 0.349 373.7

Checkpoint sometimes worked, sometimes failed.

> Error: C stack usage 12321689 is too close to the limit Execution halted

``` r
timeTheWork(200, d0, fCheckpoint, TRUE)
```

Persist version never returns (crashes cluster interface?).

``` r
timeTheWork(200, d0, fPersist, TRUE)
```

``` r
spark_disconnect(sc)
```
