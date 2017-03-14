

library("sparklyr")
library("dplyr")
sc <- spark_connect(master = "local", 
                    version = "2.0.0",
                    hadoop_version="2.7")
iris_tbl <- dplyr::copy_to(sc, iris, "iris", 
                    overwrite= TRUE)


str(iris)
str(iris_tbl)

glimpse(iris_tbl)

summary(iris)
summary(iris_tbl)

broom::glance(iris_tbl)

library("replyr")
replyr_summary(iris_tbl)


library("tidyr")
iris %>% nest(-Species)

iris_tbl %>% nest(-Species)

iris_tbl %>%
  group_by(Species) %>%
  summarize_all(funs(typical=mean))

iris_tbl %>%
  group_by(Species) %>%
  summarize_all(funs(typical=mean)) %>%
  show_query

iris_tbl %>%
  head %>%
  show_query


iris %>%
  summarize(mx = median(Sepal.Length))

iris_tbl %>%
  summarize(mx = median(Sepal_Length))

iris_tbl %>%
  summarize(mx = mean(Sepal_Length))

DBI::dbListTables(sc)
dplyr::tbl(sc, 'iris')


