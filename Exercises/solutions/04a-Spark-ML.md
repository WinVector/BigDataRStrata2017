Overview
========

You can use `sparklyr` to fit a wide variety of machine learning algorithms in Apache Spark. This analysis compares the performance of six classification models in Apache Spark on the [Titanic](https://www.kaggle.com/c/titanic) data set.

Compare the following 6 models:

-   Random forest - `ml_random_forest`
-   Decision tree - `ml_decision_tree`
-   Gradient boosted trees - `ml_gradient_boosted_trees`
-   Logistic regression - `ml_logistic_regression`
-   Multilayer perceptron (neural net) - `ml_multilayer_perceptron`
-   Naive Bayes - `ml_naive_bayes`

Load the data
=============

Parquet is a column based data format that is also compressed. It is a format often used with Spark. Load the Titanic Parquet data into a local spark cluster.

``` r
# Connect to local spark cluster and load data
sc <- spark_connect(master = "local", version = "2.0.0")
spark_read_parquet(sc, name = "titanic", path = "datainputs/titanic-parquet")
```

    ## Source:   query [891 x 12]
    ## Database: spark connection master=local[4] app=sparklyr local=TRUE
    ## 
    ##    PassengerId Survived Pclass
    ##          <int>    <int>  <int>
    ## 1            1        0      3
    ## 2            2        1      1
    ## 3            3        1      3
    ## 4            4        1      1
    ## 5            5        0      3
    ## 6            6        0      3
    ## 7            7        0      1
    ## 8            8        0      3
    ## 9            9        1      3
    ## 10          10        1      2
    ## # ... with 881 more rows, and 9 more variables: Name <chr>, Sex <chr>,
    ## #   Age <dbl>, SibSp <int>, Parch <int>, Ticket <chr>, Fare <dbl>,
    ## #   Cabin <chr>, Embarked <chr>

``` r
titanic_tbl <- tbl(sc, "titanic")
```

------------------------------------------------------------------------

Tidy the data
=============

Tidy the data in preparation for model fitting. `sparklyr` uses `dplyr` syntax when connecting to the Spark SQL API and specific functions for connecting to the Spark ML API.

Spark SQL transforms
--------------------

Use feature transforms with Spark SQL. Create new features and modify existing features with `dplyr` syntax.

Create a new remote table with handle `titanic2_tbl` from `titanic_tbl` with additional (or altered) colums:

1.  Family\_Size - Family is the sum of spouse/siblings (SibSp), parents (Parch), plus themself
2.  Pclass - Format passenger class (Pclass) as character not numeric
3.  Embarked - Remove a small number of missing records
4.  Age - Impute missing age with average age

``` r
# Transform features with Spark SQL API
titanic2_tbl <- titanic_tbl %>% 
  mutate(Family_Size = SibSp + Parch + 1L) %>%  
  mutate(Pclass = as.character(Pclass)) %>%
  filter(!is.na(Embarked)) %>%
  mutate(Age = if_else(is.na(Age), mean(Age), Age)) %>%
  compute()
```

Spark ML transforms
-------------------

Use feature transforms with Spark ML. Use `ft_bucketizer` to bucket family sizes into groups.

``` r
# Transform family size with Spark ML API
titanic_final_tbl <- titanic2_tbl %>%
  mutate(Family_Size = as.numeric(Family_size)) %>%
  sdf_mutate(
    Family_Sizes = ft_bucketizer(Family_Size, splits = c(1,2,5,12))
    ) %>%
  mutate(Family_Sizes = as.character(as.integer(Family_Sizes))) %>%
  compute()
```

> Tip: You can use magrittr pipes to chain dplyr commands with sparklyr commands. For example, `mutate` is a dplyr command that accesses the Spark SQL API whereas `sdf_mutate` is a sparklyr command that accesses the Spark ML API.

Train-validation split
----------------------

Randomly partition the data into train and test sets.

``` r
# Partition the data.
# The as.numeric() conversions are because Integer and Doubles are not interchangable in Java/Scala
partition <- titanic_final_tbl %>% 
  mutate(Survived = as.numeric(Survived), SibSp = as.numeric(SibSp), Parch = as.numeric(Parch)) %>%
  select(Survived, Pclass, Sex, Age, SibSp, Parch, Fare, Embarked, Family_Sizes) %>%
  sdf_partition(train = 0.75, test = 0.25, seed = 8585)

# Create table references
train_tbl <- partition$train
test_tbl <- partition$test
```

> Tip: Use `sdf_partition` to create training and testing splits.

------------------------------------------------------------------------

Train the models
================

Train multiple machine learning algorithms on the training data. Score the test data with the fitted models.

Logistic regression
-------------------

Logistic regression is one of the most common classifiers. Train the logistic regression and examine the predictors.

``` r
# Model survival as a function of several predictors
ml_formula <- formula(Survived ~ Pclass + Sex + Age + SibSp + Parch + Fare + Embarked + Family_Sizes)

# Train a logistic regression model
(ml_log <- ml_logistic_regression(train_tbl, ml_formula))
```

    ## * No rows dropped by 'na.omit' call

    ## Call: Survived ~ Pclass_2 + Pclass_3 + Sex_male + Age + SibSp + Parch + Fare + Embarked_Q + Embarked_S + Family_Sizes_1 + Family_Sizes_2
    ## 
    ## Coefficients:
    ##    (Intercept)       Pclass_2       Pclass_3       Sex_male            Age 
    ##    3.770024202   -1.001174014   -2.077589828   -2.674074995   -0.041217932 
    ##          SibSp          Parch           Fare     Embarked_Q     Embarked_S 
    ##   -0.056016163    0.162832732    0.000293634    0.363901651   -0.101122063 
    ## Family_Sizes_1 Family_Sizes_2 
    ##    0.141765426   -1.826757360

Other ML algorithms
-------------------

Run the same formula using the other machine learning algorithms. Notice that training times vary greatly between methods.

``` r
## Decision Tree
ml_dt <- ml_decision_tree(train_tbl, ml_formula)
```

    ## * No rows dropped by 'na.omit' call

``` r
## Random Forest
ml_rf <- ml_random_forest(train_tbl, ml_formula)
```

    ## * No rows dropped by 'na.omit' call

``` r
## Gradient Boosted Trees
ml_gbt <- ml_gradient_boosted_trees(train_tbl, ml_formula)
```

    ## * No rows dropped by 'na.omit' call

``` r
## Naive Bayes
ml_nb <- ml_naive_bayes(train_tbl, ml_formula)
```

    ## * No rows dropped by 'na.omit' call

``` r
## Neural Network
ml_nn <- ml_multilayer_perceptron(train_tbl, ml_formula, layers = c(11,15,2))
```

    ## * No rows dropped by 'na.omit' call

Validation data
---------------

Score the test data with the trained models.

``` r
# Bundle the modelss into a single list object
ml_models <- list(
  "Logistic" = ml_log,
  "Decision Tree" = ml_dt,
  "Random Forest" = ml_rf,
  "Gradient Boosted Trees" = ml_gbt,
  "Naive Bayes" = ml_nb,
  "Neural Net" = ml_nn
)

# Create a function for scoring
score_test_data <- function(model, data=test_tbl){
  pred <- sdf_predict(model, data)
  select(pred, Survived, prediction)
}

# Score all the models
ml_score <- lapply(ml_models, score_test_data)
```

------------------------------------------------------------------------

Compare results
===============

Compare the model results. Examine performance metrics: lift, AUC, and accuracy. Also examine feature importance to see what features are most predictive of survival.

Model lift
----------

Lift compares how well the model predicts survival compared to random guessing. Use the function below to estimate model lift for each scored decile in the test data. The lift chart suggests that the tree models (random forest, gradient boosted trees, or the decision tree) will provide the best prediction.

For more information see the discussion on the *gain curve* in the section "Evaluating the Model" of [this post](http://www.win-vector.com/blog/2015/07/working-with-sessionized-data-1-evaluating-hazard-models/).

``` r
nbins = 20

# Lift_function
calculate_lift = function(scored_data, numbins=nbins) {
 scored_data %>%
    mutate(bin = ntile(desc(prediction), numbins)) %>% 
    group_by(bin) %>% 
    summarize(ncaptured = sum(Survived),
              ndata = n())  %>% 
    arrange(bin) %>% 
    mutate(cumulative_data_fraction=cumsum(ndata)/sum(ndata),
           cumulative_capture_rate=cumsum(ncaptured)/sum(ncaptured))  %>% 
    select(cumulative_data_fraction, cumulative_capture_rate) %>% 
    collect() %>% 
    as.data.frame()
}

# Initialize results
ml_gains <- data.frame(cumulative_data_fraction = seq(0,1,len=nbins),
                       cumulative_capture_rate=seq(0,1,len=nbins),
                       model="Random Guess")

# Calculate lift
for(i in names(ml_score)){
  ml_gains <- ml_score[[i]] %>%
    calculate_lift %>%
    mutate(model = i) %>%
    rbind(ml_gains, .)
}

# Plot results
# Note that logistic regression, Naive Bayes and Neural net are all returning HARD classification, 
# NOT probability scores. The probabilities are there for (at least) logistic, but not easily 
# manipulable through sparklyr
ggplot(ml_gains, aes(x = cumulative_data_fraction, y = cumulative_capture_rate, colour = model)) +
  geom_point() + geom_line() +
  ggtitle("Lift Chart for Predicting Survival - Test Data Set") 
```

![](04a-Spark-ML_files/figure-markdown_github/lift-1.png)

> Tip: `dplyr` and `sparklyr` both support windows functions, including `ntiles` and `cumsum`.

Suppose we want the lift curve for logistic regression, based on *probabilities*, not hard class prediction. One way to do this is to bring a sample of the data over to R and plot the lift (we will used WVPlots::GainCurvePlot).

``` r
# get the probabilities from sdf_predict()
ml_logistic <- sdf_predict(ml_models[["Logistic"]], test_tbl) %>% 
  select(Survived, prediction, probability)

# Survived is true outcome; prediction is the hard class prediction
# probability is a list of Prob(class 0), Prob(class 1)
ml_logistic
```

    ## Source:   query [219 x 3]
    ## Database: spark connection master=local[4] app=sparklyr local=TRUE
    ## 
    ##    Survived prediction probability
    ##       <dbl>      <dbl>      <list>
    ## 1         0          1   <dbl [2]>
    ## 2         0          0   <dbl [2]>
    ## 3         0          0   <dbl [2]>
    ## 4         0          0   <dbl [2]>
    ## 5         0          0   <dbl [2]>
    ## 6         0          0   <dbl [2]>
    ## 7         0          0   <dbl [2]>
    ## 8         0          0   <dbl [2]>
    ## 9         0          0   <dbl [2]>
    ## 10        0          0   <dbl [2]>
    ## # ... with 209 more rows

``` r
# Let's take a "sample" of ml_logistic to bring over. This data happens to
# be small, so we'll take the whole thing, but in real-world situations you
# would of course use a fraction < 1
fraction = 1
ml_logistic_sample = sdf_sample(ml_logistic, fraction, replacement=FALSE) %>%
  collect()  # collect() brings the data to local R

# add a column -- the probability of class 1 (survived)
ml_logistic_sample$score = vapply(ml_logistic_sample$probability, 
                                  function(ri) { ri[[2]] }, numeric(1))

WVPlots::GainCurvePlot(ml_logistic_sample, 
                             "score", "Survived", 
                             "Gain Curve Plot, logistic model")
```

![](04a-Spark-ML_files/figure-markdown_github/locallift-1.png)

``` r
WVPlots::ROCPlot(ml_logistic_sample, 
                             "score", "Survived", 1,
                             "ROC Plot, logistic model")
```

![](04a-Spark-ML_files/figure-markdown_github/locallift-2.png)

``` r
# if on dev version of WVPlots
rocFrame <- WVPlots::graphROC(ml_logistic_sample$score, 
                              ml_logistic_sample$Survived==1)
plot_ly(rocFrame$pointGraph, x = ~FalsePositiveRate, y = ~TruePositiveRate, 
        type='scatter', mode='markers', hoverinfo= 'text', 
        text= ~ paste('threshold:', model, 
                      '</br>FalsePositiveRate:', FalsePositiveRate,
                      '</br>TruePositiveRate:', TruePositiveRate))
```

<!--html_preserve-->

<script type="application/json" data-for="htmlwidget-3741f990701a42390714">{"x":{"layout":{"margin":{"b":40,"l":60,"t":25,"r":10},"xaxis":{"domain":[0,1],"title":"FalsePositiveRate"},"yaxis":{"domain":[0,1],"title":"TruePositiveRate"},"hovermode":"closest"},"source":"A","config":{"modeBarButtonsToAdd":[{"name":"Collaborate","icon":{"width":1000,"ascent":500,"descent":-50,"path":"M487 375c7-10 9-23 5-36l-79-259c-3-12-11-23-22-31-11-8-22-12-35-12l-263 0c-15 0-29 5-43 15-13 10-23 23-28 37-5 13-5 25-1 37 0 0 0 3 1 7 1 5 1 8 1 11 0 2 0 4-1 6 0 3-1 5-1 6 1 2 2 4 3 6 1 2 2 4 4 6 2 3 4 5 5 7 5 7 9 16 13 26 4 10 7 19 9 26 0 2 0 5 0 9-1 4-1 6 0 8 0 2 2 5 4 8 3 3 5 5 5 7 4 6 8 15 12 26 4 11 7 19 7 26 1 1 0 4 0 9-1 4-1 7 0 8 1 2 3 5 6 8 4 4 6 6 6 7 4 5 8 13 13 24 4 11 7 20 7 28 1 1 0 4 0 7-1 3-1 6-1 7 0 2 1 4 3 6 1 1 3 4 5 6 2 3 3 5 5 6 1 2 3 5 4 9 2 3 3 7 5 10 1 3 2 6 4 10 2 4 4 7 6 9 2 3 4 5 7 7 3 2 7 3 11 3 3 0 8 0 13-1l0-1c7 2 12 2 14 2l218 0c14 0 25-5 32-16 8-10 10-23 6-37l-79-259c-7-22-13-37-20-43-7-7-19-10-37-10l-248 0c-5 0-9-2-11-5-2-3-2-7 0-12 4-13 18-20 41-20l264 0c5 0 10 2 16 5 5 3 8 6 10 11l85 282c2 5 2 10 2 17 7-3 13-7 17-13z m-304 0c-1-3-1-5 0-7 1-1 3-2 6-2l174 0c2 0 4 1 7 2 2 2 4 4 5 7l6 18c0 3 0 5-1 7-1 1-3 2-6 2l-173 0c-3 0-5-1-8-2-2-2-4-4-4-7z m-24-73c-1-3-1-5 0-7 2-2 3-2 6-2l174 0c2 0 5 0 7 2 3 2 4 4 5 7l6 18c1 2 0 5-1 6-1 2-3 3-5 3l-174 0c-3 0-5-1-7-3-3-1-4-4-5-6z"},"click":"function(gd) { \n        // is this being viewed in RStudio?\n        if (location.search == '?viewer_pane=1') {\n          alert('To learn about plotly for collaboration, visit:\\n https://cpsievert.github.io/plotly_book/plot-ly-for-collaboration.html');\n        } else {\n          window.open('https://cpsievert.github.io/plotly_book/plot-ly-for-collaboration.html', '_blank');\n        }\n      }"}],"modeBarButtonsToRemove":["sendDataToCloud"]},"data":[{"x":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.00719424460431655,0.0143884892086331,0.0215827338129496,0.0215827338129496,0.0215827338129496,0.0287769784172662,0.0359712230215827,0.0359712230215827,0.0431654676258993,0.0431654676258993,0.0431654676258993,0.0431654676258993,0.0503597122302158,0.0503597122302158,0.0503597122302158,0.0503597122302158,0.0575539568345324,0.0647482014388489,0.0647482014388489,0.0719424460431655,0.0719424460431655,0.079136690647482,0.079136690647482,0.079136690647482,0.0863309352517986,0.0863309352517986,0.0935251798561151,0.100719424460432,0.100719424460432,0.100719424460432,0.100719424460432,0.100719424460432,0.100719424460432,0.107913669064748,0.107913669064748,0.115107913669065,0.115107913669065,0.115107913669065,0.115107913669065,0.122302158273381,0.129496402877698,0.129496402877698,0.136690647482014,0.143884892086331,0.151079136690647,0.158273381294964,0.165467625899281,0.172661870503597,0.179856115107914,0.18705035971223,0.194244604316547,0.194244604316547,0.201438848920863,0.201438848920863,0.20863309352518,0.215827338129496,0.223021582733813,0.23021582733813,0.237410071942446,0.237410071942446,0.244604316546763,0.244604316546763,0.251798561151079,0.258992805755396,0.258992805755396,0.266187050359712,0.273381294964029,0.280575539568345,0.287769784172662,0.294964028776978,0.294964028776978,0.294964028776978,0.302158273381295,0.309352517985612,0.316546762589928,0.323741007194245,0.330935251798561,0.330935251798561,0.338129496402878,0.352517985611511,0.359712230215827,0.366906474820144,0.37410071942446,0.388489208633094,0.39568345323741,0.402877697841727,0.402877697841727,0.410071942446043,0.41726618705036,0.424460431654676,0.431654676258993,0.438848920863309,0.446043165467626,0.453237410071942,0.460431654676259,0.467625899280576,0.474820143884892,0.482014388489209,0.489208633093525,0.496402877697842,0.503597122302158,0.510791366906475,0.517985611510791,0.525179856115108,0.532374100719424,0.539568345323741,0.539568345323741,0.546762589928058,0.553956834532374,0.561151079136691,0.568345323741007,0.575539568345324,0.58273381294964,0.58273381294964,0.589928057553957,0.597122302158273,0.60431654676259,0.611510791366906,0.618705035971223,0.62589928057554,0.633093525179856,0.640287769784173,0.647482014388489,0.654676258992806,0.654676258992806,0.661870503597122,0.669064748201439,0.676258992805755,0.676258992805755,0.697841726618705,0.705035971223022,0.712230215827338,0.719424460431655,0.726618705035971,0.733812949640288,0.741007194244604,0.748201438848921,0.755395683453237,0.776978417266187,0.805755395683453,0.820143884892086,0.827338129496403,0.834532374100719,0.841726618705036,0.841726618705036,0.848920863309353,0.856115107913669,0.863309352517986,0.870503597122302,0.877697841726619,0.884892086330935,0.892086330935252,0.906474820143885,0.913669064748201,0.920863309352518,0.928057553956835,0.935251798561151,0.935251798561151,0.942446043165468,0.949640287769784,0.956834532374101,0.964028776978417,0.971223021582734,0.97841726618705,0.985611510791367,0.992805755395683,1],"y":[0.0125,0.025,0.0375,0.05,0.0625,0.075,0.0875,0.1,0.1125,0.125,0.1375,0.15,0.1625,0.175,0.1875,0.2,0.2125,0.225,0.2375,0.25,0.2625,0.275,0.2875,0.3,0.3125,0.325,0.3375,0.35,0.3625,0.3625,0.375,0.3875,0.4,0.4125,0.425,0.4375,0.45,0.4625,0.475,0.4875,0.4875,0.4875,0.5,0.5125,0.5125,0.5125,0.525,0.525,0.5375,0.55,0.5625,0.5625,0.575,0.5875,0.6,0.6,0.6,0.6125,0.6125,0.625,0.625,0.6375,0.65,0.65,0.6625,0.6625,0.6625,0.675,0.6875,0.7,0.7125,0.725,0.725,0.7375,0.7375,0.75,0.7625,0.775,0.775,0.775,0.7875,0.7875,0.7875,0.7875,0.7875,0.7875,0.7875,0.7875,0.7875,0.7875,0.8,0.8,0.8125,0.8125,0.8125,0.8125,0.8125,0.8125,0.825,0.825,0.8375,0.8375,0.8375,0.85,0.85,0.85,0.85,0.85,0.85,0.8625,0.875,0.875,0.875,0.875,0.875,0.875,0.8875,0.8875,0.8875,0.8875,0.8875,0.8875,0.8875,0.8875,0.8875,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9125,0.9125,0.9125,0.9125,0.9125,0.9125,0.925,0.925,0.925,0.925,0.925,0.925,0.925,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.9375,0.95,0.95,0.95,0.95,0.9625,0.9625,0.9625,0.9625,0.9625,0.9625,0.9625,0.9625,0.975,0.975,0.975,0.975,0.975,0.975,0.975,0.975,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,0.9875,1,1,1,1,1,1,1,1,1,1],"mode":"markers","hoverinfo":"text","text":["threshold: 0.966460286585269 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.0125","threshold: 0.95558812857627 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.025","threshold: 0.949837463846143 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.0375","threshold: 0.948190780346173 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.05","threshold: 0.942737540867763 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.0625","threshold: 0.940914371338042 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.075","threshold: 0.940374337885484 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.0875","threshold: 0.934509448091902 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.1","threshold: 0.931583956772931 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.1125","threshold: 0.92904490279477 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.125","threshold: 0.929004313458076 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.1375","threshold: 0.927587124155925 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.15","threshold: 0.927074050214378 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.1625","threshold: 0.922259639210559 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.175","threshold: 0.921276533969908 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.1875","threshold: 0.911857980877603 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.2","threshold: 0.906408614023723 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.2125","threshold: 0.889574904190361 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.225","threshold: 0.888118902622782 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.2375","threshold: 0.882677257554023 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.25","threshold: 0.880342026128762 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.2625","threshold: 0.877622545718686 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.275","threshold: 0.869287180786073 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.2875","threshold: 0.869008663323068 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.3","threshold: 0.865266832150923 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.3125","threshold: 0.861151551889597 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.325","threshold: 0.860215697743384 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.3375","threshold: 0.858385593233923 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.35","threshold: 0.857029777064454 \u003c/br>FalsePositiveRate: 0 \u003c/br>TruePositiveRate: 0.3625","threshold: 0.84321083276324 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.3625","threshold: 0.83981297511092 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.375","threshold: 0.83929433201304 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.3875","threshold: 0.838385226317184 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.4","threshold: 0.820161681861274 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.4125","threshold: 0.810863736347867 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.425","threshold: 0.808520409381819 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.4375","threshold: 0.802044189297667 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.45","threshold: 0.800414297698095 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.4625","threshold: 0.797115967148878 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.475","threshold: 0.781984086083139 \u003c/br>FalsePositiveRate: 0.00719424460431655 \u003c/br>TruePositiveRate: 0.4875","threshold: 0.76728345402895 \u003c/br>FalsePositiveRate: 0.0143884892086331 \u003c/br>TruePositiveRate: 0.4875","threshold: 0.765803996566151 \u003c/br>FalsePositiveRate: 0.0215827338129496 \u003c/br>TruePositiveRate: 0.4875","threshold: 0.765093935730894 \u003c/br>FalsePositiveRate: 0.0215827338129496 \u003c/br>TruePositiveRate: 0.5","threshold: 0.735523112662218 \u003c/br>FalsePositiveRate: 0.0215827338129496 \u003c/br>TruePositiveRate: 0.5125","threshold: 0.734303456352807 \u003c/br>FalsePositiveRate: 0.0287769784172662 \u003c/br>TruePositiveRate: 0.5125","threshold: 0.729185788188644 \u003c/br>FalsePositiveRate: 0.0359712230215827 \u003c/br>TruePositiveRate: 0.5125","threshold: 0.720036903213431 \u003c/br>FalsePositiveRate: 0.0359712230215827 \u003c/br>TruePositiveRate: 0.525","threshold: 0.719173478440613 \u003c/br>FalsePositiveRate: 0.0431654676258993 \u003c/br>TruePositiveRate: 0.525","threshold: 0.714851387863181 \u003c/br>FalsePositiveRate: 0.0431654676258993 \u003c/br>TruePositiveRate: 0.5375","threshold: 0.710173560455325 \u003c/br>FalsePositiveRate: 0.0431654676258993 \u003c/br>TruePositiveRate: 0.55","threshold: 0.700900692696864 \u003c/br>FalsePositiveRate: 0.0431654676258993 \u003c/br>TruePositiveRate: 0.5625","threshold: 0.697820294420257 \u003c/br>FalsePositiveRate: 0.0503597122302158 \u003c/br>TruePositiveRate: 0.5625","threshold: 0.697798622767116 \u003c/br>FalsePositiveRate: 0.0503597122302158 \u003c/br>TruePositiveRate: 0.575","threshold: 0.697795526744739 \u003c/br>FalsePositiveRate: 0.0503597122302158 \u003c/br>TruePositiveRate: 0.5875","threshold: 0.693574767017367 \u003c/br>FalsePositiveRate: 0.0503597122302158 \u003c/br>TruePositiveRate: 0.6","threshold: 0.690287722838835 \u003c/br>FalsePositiveRate: 0.0575539568345324 \u003c/br>TruePositiveRate: 0.6","threshold: 0.683412135593112 \u003c/br>FalsePositiveRate: 0.0647482014388489 \u003c/br>TruePositiveRate: 0.6","threshold: 0.666519568543519 \u003c/br>FalsePositiveRate: 0.0647482014388489 \u003c/br>TruePositiveRate: 0.6125","threshold: 0.665434130096044 \u003c/br>FalsePositiveRate: 0.0719424460431655 \u003c/br>TruePositiveRate: 0.6125","threshold: 0.66525324057702 \u003c/br>FalsePositiveRate: 0.0719424460431655 \u003c/br>TruePositiveRate: 0.625","threshold: 0.656771629018009 \u003c/br>FalsePositiveRate: 0.079136690647482 \u003c/br>TruePositiveRate: 0.625","threshold: 0.647921343120849 \u003c/br>FalsePositiveRate: 0.079136690647482 \u003c/br>TruePositiveRate: 0.6375","threshold: 0.638339710930342 \u003c/br>FalsePositiveRate: 0.079136690647482 \u003c/br>TruePositiveRate: 0.65","threshold: 0.63718038751048 \u003c/br>FalsePositiveRate: 0.0863309352517986 \u003c/br>TruePositiveRate: 0.65","threshold: 0.617926189486439 \u003c/br>FalsePositiveRate: 0.0863309352517986 \u003c/br>TruePositiveRate: 0.6625","threshold: 0.612193753095542 \u003c/br>FalsePositiveRate: 0.0935251798561151 \u003c/br>TruePositiveRate: 0.6625","threshold: 0.599790220507772 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.6625","threshold: 0.554501789243667 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.675","threshold: 0.553180558920983 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.6875","threshold: 0.552182197469343 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.7","threshold: 0.541760920948256 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.7125","threshold: 0.489409685349597 \u003c/br>FalsePositiveRate: 0.100719424460432 \u003c/br>TruePositiveRate: 0.725","threshold: 0.471478834850221 \u003c/br>FalsePositiveRate: 0.107913669064748 \u003c/br>TruePositiveRate: 0.725","threshold: 0.47075451606901 \u003c/br>FalsePositiveRate: 0.107913669064748 \u003c/br>TruePositiveRate: 0.7375","threshold: 0.466938212164634 \u003c/br>FalsePositiveRate: 0.115107913669065 \u003c/br>TruePositiveRate: 0.7375","threshold: 0.462202506733302 \u003c/br>FalsePositiveRate: 0.115107913669065 \u003c/br>TruePositiveRate: 0.75","threshold: 0.455011415905697 \u003c/br>FalsePositiveRate: 0.115107913669065 \u003c/br>TruePositiveRate: 0.7625","threshold: 0.451096553217281 \u003c/br>FalsePositiveRate: 0.115107913669065 \u003c/br>TruePositiveRate: 0.775","threshold: 0.448410080463954 \u003c/br>FalsePositiveRate: 0.122302158273381 \u003c/br>TruePositiveRate: 0.775","threshold: 0.44657755906918 \u003c/br>FalsePositiveRate: 0.129496402877698 \u003c/br>TruePositiveRate: 0.775","threshold: 0.445714132524291 \u003c/br>FalsePositiveRate: 0.129496402877698 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.445427605102725 \u003c/br>FalsePositiveRate: 0.136690647482014 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.444777617662423 \u003c/br>FalsePositiveRate: 0.143884892086331 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.443502655994282 \u003c/br>FalsePositiveRate: 0.151079136690647 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.436366059368134 \u003c/br>FalsePositiveRate: 0.158273381294964 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.435064086543498 \u003c/br>FalsePositiveRate: 0.165467625899281 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.408065466307443 \u003c/br>FalsePositiveRate: 0.172661870503597 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.406098896491594 \u003c/br>FalsePositiveRate: 0.179856115107914 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.40548076597244 \u003c/br>FalsePositiveRate: 0.18705035971223 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.378570013379409 \u003c/br>FalsePositiveRate: 0.194244604316547 \u003c/br>TruePositiveRate: 0.7875","threshold: 0.367335327745796 \u003c/br>FalsePositiveRate: 0.194244604316547 \u003c/br>TruePositiveRate: 0.8","threshold: 0.359379550802442 \u003c/br>FalsePositiveRate: 0.201438848920863 \u003c/br>TruePositiveRate: 0.8","threshold: 0.33362094607619 \u003c/br>FalsePositiveRate: 0.201438848920863 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.321935140107734 \u003c/br>FalsePositiveRate: 0.20863309352518 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.315777392036759 \u003c/br>FalsePositiveRate: 0.215827338129496 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.313717299631197 \u003c/br>FalsePositiveRate: 0.223021582733813 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.312941232050773 \u003c/br>FalsePositiveRate: 0.23021582733813 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.310563674543564 \u003c/br>FalsePositiveRate: 0.237410071942446 \u003c/br>TruePositiveRate: 0.8125","threshold: 0.307503617372545 \u003c/br>FalsePositiveRate: 0.237410071942446 \u003c/br>TruePositiveRate: 0.825","threshold: 0.305634562795301 \u003c/br>FalsePositiveRate: 0.244604316546763 \u003c/br>TruePositiveRate: 0.825","threshold: 0.305495448466376 \u003c/br>FalsePositiveRate: 0.244604316546763 \u003c/br>TruePositiveRate: 0.8375","threshold: 0.302467373201862 \u003c/br>FalsePositiveRate: 0.251798561151079 \u003c/br>TruePositiveRate: 0.8375","threshold: 0.299526051924982 \u003c/br>FalsePositiveRate: 0.258992805755396 \u003c/br>TruePositiveRate: 0.8375","threshold: 0.298974956373208 \u003c/br>FalsePositiveRate: 0.258992805755396 \u003c/br>TruePositiveRate: 0.85","threshold: 0.282699424269823 \u003c/br>FalsePositiveRate: 0.266187050359712 \u003c/br>TruePositiveRate: 0.85","threshold: 0.2787758229257 \u003c/br>FalsePositiveRate: 0.273381294964029 \u003c/br>TruePositiveRate: 0.85","threshold: 0.278628251889009 \u003c/br>FalsePositiveRate: 0.280575539568345 \u003c/br>TruePositiveRate: 0.85","threshold: 0.276096822846533 \u003c/br>FalsePositiveRate: 0.287769784172662 \u003c/br>TruePositiveRate: 0.85","threshold: 0.270564587051731 \u003c/br>FalsePositiveRate: 0.294964028776978 \u003c/br>TruePositiveRate: 0.85","threshold: 0.269513521105535 \u003c/br>FalsePositiveRate: 0.294964028776978 \u003c/br>TruePositiveRate: 0.8625","threshold: 0.268430111514955 \u003c/br>FalsePositiveRate: 0.294964028776978 \u003c/br>TruePositiveRate: 0.875","threshold: 0.262507179571477 \u003c/br>FalsePositiveRate: 0.302158273381295 \u003c/br>TruePositiveRate: 0.875","threshold: 0.25942365291356 \u003c/br>FalsePositiveRate: 0.309352517985612 \u003c/br>TruePositiveRate: 0.875","threshold: 0.254337020722134 \u003c/br>FalsePositiveRate: 0.316546762589928 \u003c/br>TruePositiveRate: 0.875","threshold: 0.247917254479403 \u003c/br>FalsePositiveRate: 0.323741007194245 \u003c/br>TruePositiveRate: 0.875","threshold: 0.246862970098049 \u003c/br>FalsePositiveRate: 0.330935251798561 \u003c/br>TruePositiveRate: 0.875","threshold: 0.242403088874526 \u003c/br>FalsePositiveRate: 0.330935251798561 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.230899049154607 \u003c/br>FalsePositiveRate: 0.338129496402878 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.226508427693941 \u003c/br>FalsePositiveRate: 0.352517985611511 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.220422961269035 \u003c/br>FalsePositiveRate: 0.359712230215827 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.218572349698414 \u003c/br>FalsePositiveRate: 0.366906474820144 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.216535727819826 \u003c/br>FalsePositiveRate: 0.37410071942446 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.211511079739266 \u003c/br>FalsePositiveRate: 0.388489208633094 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.206000397396185 \u003c/br>FalsePositiveRate: 0.39568345323741 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.203763822191326 \u003c/br>FalsePositiveRate: 0.402877697841727 \u003c/br>TruePositiveRate: 0.8875","threshold: 0.199854242715541 \u003c/br>FalsePositiveRate: 0.402877697841727 \u003c/br>TruePositiveRate: 0.9","threshold: 0.197991097191979 \u003c/br>FalsePositiveRate: 0.410071942446043 \u003c/br>TruePositiveRate: 0.9","threshold: 0.193173294409861 \u003c/br>FalsePositiveRate: 0.41726618705036 \u003c/br>TruePositiveRate: 0.9","threshold: 0.192843168804722 \u003c/br>FalsePositiveRate: 0.424460431654676 \u003c/br>TruePositiveRate: 0.9","threshold: 0.189238060460581 \u003c/br>FalsePositiveRate: 0.431654676258993 \u003c/br>TruePositiveRate: 0.9","threshold: 0.186873804111176 \u003c/br>FalsePositiveRate: 0.438848920863309 \u003c/br>TruePositiveRate: 0.9","threshold: 0.184410814398905 \u003c/br>FalsePositiveRate: 0.446043165467626 \u003c/br>TruePositiveRate: 0.9","threshold: 0.172192388729035 \u003c/br>FalsePositiveRate: 0.453237410071942 \u003c/br>TruePositiveRate: 0.9","threshold: 0.166584592301134 \u003c/br>FalsePositiveRate: 0.460431654676259 \u003c/br>TruePositiveRate: 0.9","threshold: 0.165067270430986 \u003c/br>FalsePositiveRate: 0.467625899280576 \u003c/br>TruePositiveRate: 0.9","threshold: 0.16194558883118 \u003c/br>FalsePositiveRate: 0.474820143884892 \u003c/br>TruePositiveRate: 0.9","threshold: 0.151029133149252 \u003c/br>FalsePositiveRate: 0.482014388489209 \u003c/br>TruePositiveRate: 0.9","threshold: 0.149327435865887 \u003c/br>FalsePositiveRate: 0.489208633093525 \u003c/br>TruePositiveRate: 0.9","threshold: 0.141265214542519 \u003c/br>FalsePositiveRate: 0.496402877697842 \u003c/br>TruePositiveRate: 0.9","threshold: 0.13737696655746 \u003c/br>FalsePositiveRate: 0.503597122302158 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.137376385449332 \u003c/br>FalsePositiveRate: 0.510791366906475 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.137376096635881 \u003c/br>FalsePositiveRate: 0.517985611510791 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.134363426372978 \u003c/br>FalsePositiveRate: 0.525179856115108 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.134294709245802 \u003c/br>FalsePositiveRate: 0.532374100719424 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.134277357960225 \u003c/br>FalsePositiveRate: 0.539568345323741 \u003c/br>TruePositiveRate: 0.9125","threshold: 0.131665360618261 \u003c/br>FalsePositiveRate: 0.539568345323741 \u003c/br>TruePositiveRate: 0.925","threshold: 0.129618985748925 \u003c/br>FalsePositiveRate: 0.546762589928058 \u003c/br>TruePositiveRate: 0.925","threshold: 0.129609876050266 \u003c/br>FalsePositiveRate: 0.553956834532374 \u003c/br>TruePositiveRate: 0.925","threshold: 0.129570958930166 \u003c/br>FalsePositiveRate: 0.561151079136691 \u003c/br>TruePositiveRate: 0.925","threshold: 0.129564474814374 \u003c/br>FalsePositiveRate: 0.568345323741007 \u003c/br>TruePositiveRate: 0.925","threshold: 0.125737403647973 \u003c/br>FalsePositiveRate: 0.575539568345324 \u003c/br>TruePositiveRate: 0.925","threshold: 0.124986564947734 \u003c/br>FalsePositiveRate: 0.58273381294964 \u003c/br>TruePositiveRate: 0.925","threshold: 0.124513270507417 \u003c/br>FalsePositiveRate: 0.58273381294964 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.123108915556673 \u003c/br>FalsePositiveRate: 0.589928057553957 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.121213305654193 \u003c/br>FalsePositiveRate: 0.597122302158273 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.120554100805617 \u003c/br>FalsePositiveRate: 0.60431654676259 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.120546187450774 \u003c/br>FalsePositiveRate: 0.611510791366906 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.120529197977527 \u003c/br>FalsePositiveRate: 0.618705035971223 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.1187279881097 \u003c/br>FalsePositiveRate: 0.62589928057554 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.116888081867679 \u003c/br>FalsePositiveRate: 0.633093525179856 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.116246128955601 \u003c/br>FalsePositiveRate: 0.640287769784173 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.112408367556068 \u003c/br>FalsePositiveRate: 0.647482014388489 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.10803567157614 \u003c/br>FalsePositiveRate: 0.654676258992806 \u003c/br>TruePositiveRate: 0.9375","threshold: 0.105473025339395 \u003c/br>FalsePositiveRate: 0.654676258992806 \u003c/br>TruePositiveRate: 0.95","threshold: 0.105388932651276 \u003c/br>FalsePositiveRate: 0.661870503597122 \u003c/br>TruePositiveRate: 0.95","threshold: 0.104138399879854 \u003c/br>FalsePositiveRate: 0.669064748201439 \u003c/br>TruePositiveRate: 0.95","threshold: 0.0996510436404809 \u003c/br>FalsePositiveRate: 0.676258992805755 \u003c/br>TruePositiveRate: 0.95","threshold: 0.099633483407571 \u003c/br>FalsePositiveRate: 0.676258992805755 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0996333727757643 \u003c/br>FalsePositiveRate: 0.697841726618705 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0983179070690638 \u003c/br>FalsePositiveRate: 0.705035971223022 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0983177977385414 \u003c/br>FalsePositiveRate: 0.712230215827338 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0967319808899972 \u003c/br>FalsePositiveRate: 0.719424460431655 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0966908309688299 \u003c/br>FalsePositiveRate: 0.726618705035971 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0931496303179371 \u003c/br>FalsePositiveRate: 0.733812949640288 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0927592574306693 \u003c/br>FalsePositiveRate: 0.741007194244604 \u003c/br>TruePositiveRate: 0.9625","threshold: 0.0921250838951759 \u003c/br>FalsePositiveRate: 0.748201438848921 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0910988846438281 \u003c/br>FalsePositiveRate: 0.755395683453237 \u003c/br>TruePositiveRate: 0.975","threshold: 0.090942188121792 \u003c/br>FalsePositiveRate: 0.776978417266187 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0909384449521428 \u003c/br>FalsePositiveRate: 0.805755395683453 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0909227698115143 \u003c/br>FalsePositiveRate: 0.820143884892086 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0909179158170367 \u003c/br>FalsePositiveRate: 0.827338129496403 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0897299359964019 \u003c/br>FalsePositiveRate: 0.834532374100719 \u003c/br>TruePositiveRate: 0.975","threshold: 0.088060799136608 \u003c/br>FalsePositiveRate: 0.841726618705036 \u003c/br>TruePositiveRate: 0.975","threshold: 0.0832177400689476 \u003c/br>FalsePositiveRate: 0.841726618705036 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0832170859304694 \u003c/br>FalsePositiveRate: 0.848920863309353 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0830379011683436 \u003c/br>FalsePositiveRate: 0.856115107913669 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0815141589230806 \u003c/br>FalsePositiveRate: 0.863309352517986 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0801607519194052 \u003c/br>FalsePositiveRate: 0.870503597122302 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0801424413270499 \u003c/br>FalsePositiveRate: 0.877697841726619 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0801260260904813 \u003c/br>FalsePositiveRate: 0.884892086330935 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0775369335960812 \u003c/br>FalsePositiveRate: 0.892086330935252 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0742596170492859 \u003c/br>FalsePositiveRate: 0.906474820143885 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0704621379856318 \u003c/br>FalsePositiveRate: 0.913669064748201 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0673431354206539 \u003c/br>FalsePositiveRate: 0.920863309352518 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0545140888738747 \u003c/br>FalsePositiveRate: 0.928057553956835 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0527240402639634 \u003c/br>FalsePositiveRate: 0.935251798561151 \u003c/br>TruePositiveRate: 0.9875","threshold: 0.0504404000261431 \u003c/br>FalsePositiveRate: 0.935251798561151 \u003c/br>TruePositiveRate: 1","threshold: 0.0504252834350638 \u003c/br>FalsePositiveRate: 0.942446043165468 \u003c/br>TruePositiveRate: 1","threshold: 0.0478348825399489 \u003c/br>FalsePositiveRate: 0.949640287769784 \u003c/br>TruePositiveRate: 1","threshold: 0.0455843753495339 \u003c/br>FalsePositiveRate: 0.956834532374101 \u003c/br>TruePositiveRate: 1","threshold: 0.0414356325330288 \u003c/br>FalsePositiveRate: 0.964028776978417 \u003c/br>TruePositiveRate: 1","threshold: 0.0383784323547277 \u003c/br>FalsePositiveRate: 0.971223021582734 \u003c/br>TruePositiveRate: 1","threshold: 0.0374123634995541 \u003c/br>FalsePositiveRate: 0.97841726618705 \u003c/br>TruePositiveRate: 1","threshold: 0.0289588832532782 \u003c/br>FalsePositiveRate: 0.985611510791367 \u003c/br>TruePositiveRate: 1","threshold: 0.0261200385365301 \u003c/br>FalsePositiveRate: 0.992805755395683 \u003c/br>TruePositiveRate: 1","threshold: 0.0158188668804034 \u003c/br>FalsePositiveRate: 1 \u003c/br>TruePositiveRate: 1"],"type":"scatter","marker":{"fillcolor":"rgba(31,119,180,1)","color":"rgba(31,119,180,1)","line":{"color":"transparent"}},"xaxis":"x","yaxis":"y"}],"base_url":"https://plot.ly"},"evals":["config.modeBarButtonsToAdd.0.click"],"jsHooks":[]}</script>
<!--/html_preserve-->
``` r
# compare this graph (not the previous ones) to balanced accuracy
# http://www.win-vector.com/blog/2016/07/a-budget-of-classifier-evaluation-measures/
ml_logistic_sample <- ml_logistic_sample %>% mutate(qscore = ifelse(score>0.5, 1.0, 0.0))
WVPlots::ROCPlot(ml_logistic_sample, 
                             "qscore", "Survived", 1,
                             "ROC Plot, logistic decision")
```

![](04a-Spark-ML_files/figure-markdown_github/locallift-4.png)

``` r
# As long as we have it, let's call caret on the local score data.
tab = table(pred = as.character(ml_logistic_sample$prediction==1), 
            lbsurvived = as.character(ml_logistic_sample$Survived==1))
print(tab)
```

    ##        lbsurvived
    ## pred    FALSE TRUE
    ##   FALSE   125   23
    ##   TRUE     14   57

``` r
# this only works if the package e1071 is loaded
caret::confusionMatrix(tab,
            positive= 'TRUE')
```

    ## Confusion Matrix and Statistics
    ## 
    ##        lbsurvived
    ## pred    FALSE TRUE
    ##   FALSE   125   23
    ##   TRUE     14   57
    ##                                           
    ##                Accuracy : 0.8311          
    ##                  95% CI : (0.7747, 0.8782)
    ##     No Information Rate : 0.6347          
    ##     P-Value [Acc > NIR] : 1.339e-10       
    ##                                           
    ##                   Kappa : 0.6267          
    ##  Mcnemar's Test P-Value : 0.1884          
    ##                                           
    ##             Sensitivity : 0.7125          
    ##             Specificity : 0.8993          
    ##          Pos Pred Value : 0.8028          
    ##          Neg Pred Value : 0.8446          
    ##              Prevalence : 0.3653          
    ##          Detection Rate : 0.2603          
    ##    Detection Prevalence : 0.3242          
    ##       Balanced Accuracy : 0.8059          
    ##                                           
    ##        'Positive' Class : TRUE            
    ## 

AUC and accuracy
----------------

Though ROC curves are not available, Spark ML does have support for Area Under the ROC curve. This metric captures performance for specific cut-off values. The higher the AUC the better.

``` r
# Function for calculating accuracy
calc_accuracy <- function(data, cutpoint = 0.5){
  data %>% 
    mutate(prediction = if_else(prediction > cutpoint, 1.0, 0.0)) %>%
    ml_classification_eval("prediction", "Survived", "accuracy")
}

# Calculate AUC and accuracy
perf_metrics <- data.frame(
  model = names(ml_score),
  AUC = sapply(ml_score, ml_binary_classification_eval, "Survived", "prediction"),
  Accuracy = sapply(ml_score, calc_accuracy),
  row.names = NULL, stringsAsFactors = FALSE)

# Plot results
gather(perf_metrics, metric, value, AUC, Accuracy) %>%
  ggplot(aes(reorder(model, value, FUN=mean), value)) + 
  geom_pointrange(aes(ymin=0, ymax=value)) + 
  facet_wrap(~metric, ncol=1, scale="free_x") + 
  xlab("Model") +
  ylab("Score") +
  ggtitle("Performance Metrics (Larger is better)")  +
  coord_flip(ylim=c(0,1))
```

![](04a-Spark-ML_files/figure-markdown_github/auc-1.png)

Feature importance
------------------

It is also interesting to compare the features that were identified by each model as being important predictors for survival. The logistic regression and tree models implement feature importance metrics. Sex, fare, and age are some of the most important features.

``` r
# Initialize results
feature_importance <- data.frame()

# Calculate feature importance
for(i in c("Decision Tree", "Random Forest", "Gradient Boosted Trees")){
  feature_importance <- ml_tree_feature_importance(sc, ml_models[[i]]) %>%
    mutate(Model = i) %>%
    mutate(importance = as.numeric(levels(importance))[importance]) %>%
    mutate(feature = as.character(feature)) %>%
    rbind(feature_importance, .)
}

# Plot results
feature_importance %>%
  ggplot(aes(reorder(feature, importance), importance)) + 
  facet_wrap(~Model) +
  geom_pointrange(aes(ymin=0, ymax=importance)) + 
  coord_flip() +
  xlab("") +
  ggtitle("Feature Importance")
```

![](04a-Spark-ML_files/figure-markdown_github/importance-1.png)

------------------------------------------------------------------------

Discuss
=======

You can use `sparklyr` to run a variety of classifiers in Apache Spark. For the Titanic data, the best performing models were tree based models. Gradient boosted trees was one of the best models, but also had a much longer average run time than the other models. Random forests and decision trees both had good performance and fast run times.

While these models were run on a tiny data set in a local spark cluster, these methods will scale for analysis on data in a distributed Apache Spark cluster.
