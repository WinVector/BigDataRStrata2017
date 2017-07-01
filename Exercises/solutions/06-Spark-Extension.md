This is only a concept script, it runs correctly but is intended for teaching not direct use in production.

At some point the `SparkR:dapply()` functionality we are working to capture here will be available as a method called [`sparklyr::spark_apply()`](https://github.com/rstudio/sparklyr/pull/728).

One point in particular is this script assumes none of the following directories are present (as it is going to try to create them and write its own temp results):

-   Exercises/solutions/df\*\_tmp
-   Exercises/solutions/tmpFile\*\_\*

We don't delete these as we don't want to perform too many (potentially unsafe) file operations on the user's behalf.

``` r
Sys.setenv(TZ='UTC')
library("sparklyr")
library("dplyr")
```

    ## 
    ## Attaching package: 'dplyr'

    ## The following objects are masked from 'package:stats':
    ## 
    ##     filter, lag

    ## The following objects are masked from 'package:base':
    ## 
    ##     intersect, setdiff, setequal, union

``` r
sc <- spark_connect(master = "local", version = "2.0.0", hadoop_version="2.7")
```

``` r
d <- data_frame(x = c(20100101120101, "2009-01-02 12-01-02", "2009.01.03 12:01:03",
       "2009-1-4 12-1-4",
       "2009-1, 5 12:1, 5",
       "200901-08 1201-08",
       "2009 arbitrary 1 non-decimal 6 chars 12 in between 1 !!! 6",
       "OR collapsed formats: 20090107 120107 (as long as prefixed with zeros)",
       "Automatic wday, Thu, detection, 10-01-10 10:01:10 and p format: AM",
       "Created on 10-01-11 at 10:01:11 PM"))

df  <- copy_to(sc, d, 'df')
print(df)
```

    ## # Source:   table<df> [?? x 1]
    ## # Database: spark_connection
    ##                                                                         x
    ##                                                                     <chr>
    ##  1                                                         20100101120101
    ##  2                                                    2009-01-02 12-01-02
    ##  3                                                    2009.01.03 12:01:03
    ##  4                                                        2009-1-4 12-1-4
    ##  5                                                      2009-1, 5 12:1, 5
    ##  6                                                      200901-08 1201-08
    ##  7             2009 arbitrary 1 non-decimal 6 chars 12 in between 1 !!! 6
    ##  8 OR collapsed formats: 20090107 120107 (as long as prefixed with zeros)
    ##  9     Automatic wday, Thu, detection, 10-01-10 10:01:10 and p format: AM
    ## 10                                     Created on 10-01-11 at 10:01:11 PM

Running `SQL` directly (see <http://spark.rstudio.com>).

``` r
library("DBI")

# returns a in-memor data.frame
dfx <- dbGetQuery(sc, "SELECT * FROM df LIMIT 5")
dfx
```

    ##                     x
    ## 1      20100101120101
    ## 2 2009-01-02 12-01-02
    ## 3 2009.01.03 12:01:03
    ## 4     2009-1-4 12-1-4
    ## 5   2009-1, 5 12:1, 5

``` r
# build another table
dbSendQuery(sc, "CREATE TABLE df2 AS SELECT * FROM df LIMIT 5")
```

    ## <DBISparkResult>
    ##   SQL  CREATE TABLE df2 AS SELECT * FROM df LIMIT 5
    ##   ROWS Fetched: 0 [complete]
    ##        Changed: 0

``` r
# get a handle to it
dbListTables(sc)
```

    ## [1] "df"  "df2"

``` r
df2 <- dplyr::tbl(sc, 'df2')
df2
```

    ## # Source:   table<df2> [?? x 1]
    ## # Database: spark_connection
    ##                     x
    ##                 <chr>
    ## 1      20100101120101
    ## 2 2009-01-02 12-01-02
    ## 3 2009.01.03 12:01:03
    ## 4     2009-1-4 12-1-4
    ## 5   2009-1, 5 12:1, 5

Using `SparkR` for `R` user defined functions.

The following doesn't always run in a knitr evironment. And using `SparkR` in production would entail already having the needed R packages installed.

``` r
# Connect via SparkR, more notes: https://github.com/apache/spark/tree/master/R
SPARK_HOME <- sc$spark_home
# https://github.com/Azure/Azure-MachineLearning-DataScience/blob/master/Misc/KDDCup2016/Code/SparkR/SparkR_sparklyr_NYCTaxi.Rmd
# http://sbartek.github.io/sparkRInstall/installSparkReasyWay.html
library(SparkR, lib.loc = paste0(SPARK_HOME, "/R/lib/"))
```

    ## 
    ## Attaching package: 'SparkR'

    ## The following objects are masked from 'package:dplyr':
    ## 
    ##     arrange, between, collect, contains, count, cume_dist,
    ##     dense_rank, desc, distinct, explain, filter, first, group_by,
    ##     intersect, lag, last, lead, mutate, n, n_distinct, ntile,
    ##     percent_rank, rename, row_number, sample_frac, select, sql,
    ##     summarize, union

    ## The following objects are masked from 'package:stats':
    ## 
    ##     cov, filter, lag, na.omit, predict, sd, var, window

    ## The following objects are masked from 'package:base':
    ## 
    ##     as.data.frame, colnames, colnames<-, drop, endsWith,
    ##     intersect, rank, rbind, sample, startsWith, subset, summary,
    ##     transform, union

``` r
sr <- sparkR.session(master = "local", sparkHome = SPARK_HOME)
```

    ## Launching java with spark-submit command /Users/johnmount/Library/Caches/spark/spark-2.0.0-bin-hadoop2.7/bin/spark-submit   sparkr-shell /var/folders/7q/h_jp2vj131g5799gfnpzhdp80000gn/T//Rtmpjnl2EF/backend_port30072a4caa05

``` r
sparklyr::spark_write_parquet(df, 'df_tmp')
dSparkR <- SparkR::read.df('df_tmp')
# http://spark.apache.org/docs/latest/sparkr.html
schema <- structType(structField("dateStrOrig", "string"), 
                     structField("dateStrNorm", "timestamp"),
                     structField("dateSec", "double"))
dSparkR2 <- SparkR::dapply(dSparkR, function(x) {
  if(!require('lubridate', quietly = TRUE)) {
    install.packages("lubridate", repos= "http://cran.rstudio.com")
  }
  s <- lubridate::ymd_hms(x[[1]])
  x <- cbind(x, s, as.numeric(s))
  x
  }, schema)
SparkR::write.df(dSparkR2, 'dfR_tmp')
dfR <- sparklyr::spark_read_parquet(sc, 'dfR', 'dfR_tmp')
dfR <- dfR %>% 
  dplyr::mutate(dt = from_unixtime(dateSec)) %>%
  dplyr::select(dateStrNorm, dateSec, dt)
print(dfR)
```

    ## # Source:   lazy query [?? x 3]
    ## # Database: spark_connection
    ##              dateStrNorm    dateSec                  dt
    ##                    <chr>      <dbl>               <chr>
    ##  1 2010-01-01 12:01:01.0 1262347261 2010-01-01 12:01:01
    ##  2 2009-01-02 12:01:02.0 1230897662 2009-01-02 12:01:02
    ##  3 2009-01-03 12:01:03.0 1230984063 2009-01-03 12:01:03
    ##  4 2009-01-04 12:01:04.0 1231070464 2009-01-04 12:01:04
    ##  5 2009-01-05 12:01:05.0 1231156865 2009-01-05 12:01:05
    ##  6 2009-01-08 12:01:08.0 1231416068 2009-01-08 12:01:08
    ##  7 2009-01-06 12:01:06.0 1231243266 2009-01-06 12:01:06
    ##  8 2009-01-07 12:01:07.0 1231329667 2009-01-07 12:01:07
    ##  9 2010-01-10 10:01:10.0 1263117670 2010-01-10 10:01:10
    ## 10 2010-01-11 22:01:11.0 1263247271 2010-01-11 22:01:11

From: <http://spark.rstudio.com/extensions.html>.

``` r
count_lines <- function(sc, file) {
  spark_context(sc) %>% 
    invoke("textFile", file, 1L) %>% 
    invoke("count")
}

count_lines(sc, "tmp.csv")
```

    ## [1] 3

A simple Java example.

``` r
billionBigInteger <- invoke_new(sc, "java.math.BigInteger", "1000000000")
print(billionBigInteger)
```

    ## <jobj[147]>
    ##   class java.math.BigInteger
    ##   1000000000

``` r
str(billionBigInteger)
```

    ## Classes 'spark_jobj', 'shell_jobj' <environment: 0x7fcba37eab50>

``` r
billion <- invoke(billionBigInteger, "longValue")
str(billion)
```

    ##  num 1e+09
