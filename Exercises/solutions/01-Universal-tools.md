Markdown logistics
==================

------------------------------------------------------------------------

**Exercise 1**: *Read through this section and try out the features described below. Stop when you get to the first horizontal rule (`***`)*

These notes are an R Markdown Document that contains both text and code.

-   Add a new chunk of code by clicking the *Insert Chunk* button on the toolbar or by pressing *Cmd+Option+I*.

-   Execute a chunk by clicking the *Run* button within the chunk or by placing your cursor inside it and pressing *Cmd+Shift+Enter*. The results will appear beneath the code. To see how this works, try executing the chunk below:

``` r
paste("Hello", "world!")
```

    ## [1] "Hello world!"

When you save the document, an HTML file containing the code and output will be saved alongside it (click the *Preview* button or press *Cmd+Shift+K* to preview the HTML file).

Use Markdown syntax to format text for the HTML output. Click *Help &gt; Markdown Quick Reference* in the toolbar to open a guide in the help pane.

------------------------------------------------------------------------

dplyr
=====

The dplyr package provides a universal set of tools for data manipulation. You can use these tools to manipulate from R data that is stored in

-   R
-   databases
-   Spark

and other places. dplyr is written to be a front end with extensible backends. For more information, see [Adding a new SQL backend](https://cran.r-project.org/web/packages/dplyr/vignettes/new-sql-backend.html).

Dplyr contains ~18 functions that together form a complete grammar of data manipulation. These functions can loosely be categorized into:

Single table verbs
------------------

Single table verbs take a single data frame, reference, or tibble and return a single data frame, reference, or tibble.

-   `select` - returns a subset of columns from the data.

-   `mutate` - returns the data with one or more new columns computed from the data.

-   `filter` - return only the rows of the data that meet one or more logical conditions.

-   `arrange` - returns the data with the rows reordered by increasing (or descending with `desc()`) values of one or more variables.

-   `summarise` - returns a new data set that summarises the information in the original data set.

-   `group_by` - "splits" the data into sub-groups based on common values of a variable (or common combinations of the values of two or more variables). dplyr functions will treat each group within a grouped data set separately, which is very useful with `summarise`.

------------------------------------------------------------------------

**Exercise 2**: *The `iris` data set contains biometric measurements of three species of flower. In the code chunk below, use dplyr functions to return just the Species name, mean Petal.Width and mean Petal.Length of the Species with the largest difference between mean Petal.Width and mean Petal.Length.*

``` r
# To inspect the raw data before you begin,
# remove the hash tag below and run the chunk
# View(iris)

iris1 <- group_by(iris, Species)
iris2 <- summarise(iris1, avg_width = mean(Petal.Width), avg_length = mean(Petal.Length))
iris3 <- mutate(iris2, diff = avg_length - avg_width)
iris4 <- filter(iris3, diff == max(diff))
select(iris4, Species, avg_width, avg_length)
```

    ## # A tibble: 1 × 3
    ##     Species avg_width avg_length
    ##      <fctr>     <dbl>      <dbl>
    ## 1 virginica     2.026      5.552

------------------------------------------------------------------------

The pipe operator
-----------------

A pipe is a sequence of functions where each function passes its output to the next function to use as input. Pipes are common with dplyr, as dplyr functions are written to be composable.

The easiest way to write a pipe in R is with the `%>%` operator from the magrittr package (imported with the dplyr package). `%>%` passes the output of the expression on the left-hand side of the pipe as the first argument of the expression on the right hand side of the pipe, e.g. these two pieces of code do the same thing.

``` r
filter(iris, Sepal.Length == max(Sepal.Length))
```

    ##   Sepal.Length Sepal.Width Petal.Length Petal.Width   Species
    ## 1          7.9         3.8          6.4           2 virginica

``` r
iris %>% filter(Sepal.Length == max(Sepal.Length))
```

    ##   Sepal.Length Sepal.Width Petal.Length Petal.Width   Species
    ## 1          7.9         3.8          6.4           2 virginica

Type `%>%` with the keyboard shortcut *Cmd+Shift+M*.

------------------------------------------------------------------------

**Exercise 3**: \*You can use `%>%` to string many functions together into a long pipe. Use `%>%` to turn the code below (from Exercise 3) into a single long pipe.

``` r
iris %>%  
  group_by(Species) %>% 
  summarise(avg_width = mean(Petal.Width), avg_length = mean(Petal.Length)) %>% 
  mutate(diff = avg_length - avg_width) %>% 
  filter(diff == max(diff)) %>% 
  select(-diff)
```

    ## # A tibble: 1 × 3
    ##     Species avg_width avg_length
    ##      <fctr>     <dbl>      <dbl>
    ## 1 virginica     2.026      5.552

------------------------------------------------------------------------

Two table verbs
---------------

Two table verbs take two data frames, references, or tibbles and return a single data frame, reference, or tibble.

-   `bind_rows` - adds one data set beneath another as new rows

-   `union` - returns every row that appears in at least one of the data sets, removing duplicate rows

-   `intersect` - returns the rows that appear in both data sets

-   `setdiff` - returns the rows that appear in the first data set, but not the second

-   `bind_cols` - adds one data set beside the other as new columns

**Mutating joins** add new variables to one data set from matching rows in a second data set. dplyr has 4 mutating joins. The joins differ in the information they do not return. Mutating joins add columns from both data frames.

-   `left_join` - Takes rows from the *first* (left) data set and builds matches, if any, with the *second* (right) data set. Non-matching left rows are retained.

-   `right_join` - Same as left join with roles of *first* and *second* reversed.

-   `inner_join` - Matches only rows in both data sets.

-   `full_join` - Matches rows in either data set- even if they do have no match.

Extra credit: **Filtering joins** return rows from the first data set based on whether or not they match rows in the second data set.

-   `semi_join` - Returns rows from first data set that *match* rows in the second data set.

-   `anti_join` - Returns rows from first data set that *do not match* rows in the second data set.

------------------------------------------------------------------------

**Exercise 4**: *The code below creates two simple data sets that can be joined together. Run the chunks and examine the data sets. Then use the following chunk to test out different types of joins with the data sets and to compare their results. Use what you discover to finish the definition of each join above in your own words.*

``` r
band <- 
  data_frame(name = c("Mick", "John", "Paul"),
             band = c("Stones", "Beatles", "Beatles"),
             region = c('UK', 'UK', 'UK'))
```

``` r
instrument <- 
  data_frame(name = c("John", "Paul", "Keith"),
             plays = c("guitar", "bass", "guitar"),
             region = c('UK', 'UK', 'UK'))
```

``` r
# join
inner_join(band, instrument, by = "name")
```

    ## # A tibble: 2 × 5
    ##    name    band region.x  plays region.y
    ##   <chr>   <chr>    <chr>  <chr>    <chr>
    ## 1  John Beatles       UK guitar       UK
    ## 2  Paul Beatles       UK   bass       UK

Extra credit, explain what happens if there are duplicate keys in one or more tables?

``` r
# join
inner_join(band, instrument, by = "region")
```

    ## # A tibble: 9 × 5
    ##   name.x    band region name.y  plays
    ##    <chr>   <chr>  <chr>  <chr>  <chr>
    ## 1   Mick  Stones     UK   John guitar
    ## 2   Mick  Stones     UK   Paul   bass
    ## 3   Mick  Stones     UK  Keith guitar
    ## 4   John Beatles     UK   John guitar
    ## 5   John Beatles     UK   Paul   bass
    ## 6   John Beatles     UK  Keith guitar
    ## 7   Paul Beatles     UK   John guitar
    ## 8   Paul Beatles     UK   Paul   bass
    ## 9   Paul Beatles     UK  Keith guitar

------------------------------------------------------------------------

Airlines Project
================

The nycflights13 package contains records of every flight that departed from La Guardia (`LGA`), JFK (`JFK`) and Newark (`EWR`) airports in 2013.

The data is split into five related data sets:

1.  `flights` - arrival and departure delay information by flight (the main data set)
2.  `airlines` - airlines names by code
3.  `airports` - airport names by code
4.  `planes` - plane metadata
5.  `weather` - hourly weather data

![](nycflights.png)

**Exercise 5**: *Use the chunk below to determine which airline has the newest planes (assigned to the NYC area).*

``` r
flights %>%
  # selects distinct combinations of carrier and tailnum
  distinct(carrier, tailnum) %>%
  # join to planes to get year manufactured
  # (which column should you join on?)
  left_join(planes, by = "tailnum") %>%
  # group by carrier (e.g. the airline)
  group_by(carrier) %>%
  # calculate by carrier:
  #   1. avg - the mean year (with na.rm = TRUE) 
  #   2. n - the total number of planes
  #   3. nas - the number of planes with unknown year (year == NA)
  summarise(avg = mean(year, na.rm = TRUE), 
            n = n(), nas = sum(is.na(year))) %>%
  # join to airlines to get full airline name 
  # (which column should you join on?)
  left_join(airlines, by = "carrier") %>%
  # select just the name, avg, n, and nas variables in that order
  select(name, avg, n, nas) %>%
  # order the results by avg with the newest planes at the top
  arrange(desc(avg)) -> answer

print(answer)
```

    ## # A tibble: 16 × 4
    ##                           name      avg     n   nas
    ##                          <chr>    <dbl> <int> <int>
    ## 1       Hawaiian Airlines Inc. 2011.769    14     1
    ## 2               Virgin America 2008.712    53     1
    ## 3       Frontier Airlines Inc. 2008.000    26     3
    ## 4         Alaska Airlines Inc. 2007.843    84     1
    ## 5              JetBlue Airways 2006.503   193     6
    ## 6        SkyWest Airlines Inc. 2005.857    28     0
    ## 7            Endeavor Air Inc. 2004.713   204     2
    ## 8           Mesa Airlines Inc. 2003.561    58     1
    ## 9     ExpressJet Airlines Inc. 2002.442   316     8
    ## 10 AirTran Airways Corporation 2002.205   129    17
    ## 11             US Airways Inc. 2002.004   290    21
    ## 12      Southwest Airlines Co. 2001.995   583    14
    ## 13       United Air Lines Inc. 1999.949   621    32
    ## 14        Delta Air Lines Inc. 1995.328   629    20
    ## 15      American Airlines Inc. 1987.598   601   437
    ## 16                   Envoy Air 1977.500   238   234

``` r
library("xtable")
```

``` r
print(xtable(answer), 
      type = 'HTML' ,
      include.rownames = FALSE)
```

<!-- html table generated in R 3.3.3 by xtable 1.8-2 package -->
<!-- Thu Mar 23 08:17:10 2017 -->
<table border="1">
<tr>
<th>
name
</th>
<th>
avg
</th>
<th>
n
</th>
<th>
nas
</th>
</tr>
<tr>
<td>
Hawaiian Airlines Inc.
</td>
<td align="right">
2011.77
</td>
<td align="right">
14
</td>
<td align="right">
1
</td>
</tr>
<tr>
<td>
Virgin America
</td>
<td align="right">
2008.71
</td>
<td align="right">
53
</td>
<td align="right">
1
</td>
</tr>
<tr>
<td>
Frontier Airlines Inc.
</td>
<td align="right">
2008.00
</td>
<td align="right">
26
</td>
<td align="right">
3
</td>
</tr>
<tr>
<td>
Alaska Airlines Inc.
</td>
<td align="right">
2007.84
</td>
<td align="right">
84
</td>
<td align="right">
1
</td>
</tr>
<tr>
<td>
JetBlue Airways
</td>
<td align="right">
2006.50
</td>
<td align="right">
193
</td>
<td align="right">
6
</td>
</tr>
<tr>
<td>
SkyWest Airlines Inc.
</td>
<td align="right">
2005.86
</td>
<td align="right">
28
</td>
<td align="right">
0
</td>
</tr>
<tr>
<td>
Endeavor Air Inc.
</td>
<td align="right">
2004.71
</td>
<td align="right">
204
</td>
<td align="right">
2
</td>
</tr>
<tr>
<td>
Mesa Airlines Inc.
</td>
<td align="right">
2003.56
</td>
<td align="right">
58
</td>
<td align="right">
1
</td>
</tr>
<tr>
<td>
ExpressJet Airlines Inc.
</td>
<td align="right">
2002.44
</td>
<td align="right">
316
</td>
<td align="right">
8
</td>
</tr>
<tr>
<td>
AirTran Airways Corporation
</td>
<td align="right">
2002.21
</td>
<td align="right">
129
</td>
<td align="right">
17
</td>
</tr>
<tr>
<td>
US Airways Inc.
</td>
<td align="right">
2002.00
</td>
<td align="right">
290
</td>
<td align="right">
21
</td>
</tr>
<tr>
<td>
Southwest Airlines Co.
</td>
<td align="right">
2001.99
</td>
<td align="right">
583
</td>
<td align="right">
14
</td>
</tr>
<tr>
<td>
United Air Lines Inc.
</td>
<td align="right">
1999.95
</td>
<td align="right">
621
</td>
<td align="right">
32
</td>
</tr>
<tr>
<td>
Delta Air Lines Inc.
</td>
<td align="right">
1995.33
</td>
<td align="right">
629
</td>
<td align="right">
20
</td>
</tr>
<tr>
<td>
American Airlines Inc.
</td>
<td align="right">
1987.60
</td>
<td align="right">
601
</td>
<td align="right">
437
</td>
</tr>
<tr>
<td>
Envoy Air
</td>
<td align="right">
1977.50
</td>
<td align="right">
238
</td>
<td align="right">
234
</td>
</tr>
</table>
