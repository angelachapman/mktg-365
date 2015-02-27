library(plyr)
library(ggplot2)

dataDir = "~/mktg-365/data" ##### CHANGE ME #####

# Data set 1: Approved loans
setwd(dataDir)
ls3a = read.csv("LoanStats3a_securev1.csv")
ls3b = read.csv("LoanStats3b_securev1.csv")
ls3c = read.csv("LoanStats3c_securev1.csv")
approved = rbind(ls3a,ls3b,ls3c)
rm(list=c("ls3a","ls3b","ls3c"))
cat("Data dimensions -- approved loans:",dim(approved)[1],"x",dim(approved)[2])

# Parse the date from format jan-2000 into month and year number
approved$Year = as.numeric(substr(approved$issue_d,5,8))
mo2Num = function(x) match(tolower(x),tolower(month.abb))
approved$Month = mo2Num(substr(approved$issue_d,1,3))

# Take a look at the loan purpose. What are the most frequent loan types?
# Did the composition of loans change by year?
mytable = sort(table(approved$purpose),decreasing=TRUE)
cat("The top 10 loan types are:", names(mytable)[1:10])

# Take the top 6 as individual categories, call the rest "Other"
# (for clearer plotting)
approved$purpose[which(!(approved$purpose %in% names(mytable)[1:6]))] = "other"
df = ddply(approved,.(Year))
g = ggplot(df,aes(x=Year,fill=purpose))
g + geom_bar() +
  ggtitle("Lending Club: Approved Loans, 2007-2014") +
  xlab("Loan issue year")

# Take a look at loan status. What is the distribution of loan status by
# issue year and by loan type? Is there an obvious relationship between income,
# risk score, and loan status?
# Some records have a loan_status field that contains random junk. Omit those.
# Also, lump all the different types of late loans together (for easier plotting)
lateStatus = c("Late (31-120 days)","Late (16-30 days)", "In Grace Period")
approved$loan_status = as.character(approved$loan_status)
approved$loan_status[approved$loan_status %in% lateStatus] = "Late"
validStatus = c("Current", "Charged Off", "Fully Paid", "Late", "Default")
df = ddply(approved[approved$loan_status %in% validStatus,],.(Year))
g = ggplot(df, aes(x=Year,fill=loan_status))
g + geom_bar() +
  ggtitle("Lending Club: Status of all approved loans as of 2014") +
  xlab("Loan issue year")

table(approved$loan_status[approved$loan_status %in% validStatus])

approved = approved[approved$loan_status %in% validStatus,]
ggplot(approved, aes(x=loan_status,fill=purpose)) + geom_histogram() +
  xlab("Loan status") +
  ggtitle("Lending Club: Status of approved loans as of 2014, by loan type")

cat("Fraction of loans in default:",
    sum(approved$loan_status == "Default")/length(approved$loan_status))

cat("Fraction of loans charged off:",
    sum(approved$loan_status == "Charged Off")/length(approved$loan_status))

# Split the data into loans of "good" and "bad" standing. Remove "Late" or
# "Grace Period" loans -- only use those that are unambiguously bad or good
approved = approved[approved$loan_status %in% c("Current","Charged Off","Fully Paid",
                                                "Default"),]
approved$loan_standing = rep("Bad",length(approved$loan_status))
approved$loan_standing[approved$loan_status %in% c("Current","Fully Paid")] = "Good"
library(scales)

#Analyze if Fico Score differs by Loan Status
g = ggplot(approved,
           aes(y=annual_inc,x=(fico_range_high + fico_range_low)/2,
               color=loan_standing, shape = loan_standing))
g + geom_point() +
  ylab("Annual income") +
  xlab("FICO score") +
  ggtitle("Lending Club: Loan standing by lendee characteristics")

approved$ficoScore = (approved$fico_range_high + approved$fico_range_low)/2

ggplot(approved,aes(x=loan_standing,y=(fico_range_high + fico_range_low)/2))+geom_boxplot()

t.test(approved$ficoScore ~ approved$loan_standing)

summary(approved$ficoScore)

table(approved$loan_standing)

sum(approved$loan_standing=="Bad")/length(approved$loan_standing)


# Can we build a simple model to predict loan standing?
approved$earliestCreditYr = as.numeric(substr(approved$earliest_cr_line,5,8))
approved$avgFico = (approved$fico_range_high + approved$fico_range_low)/2
approved$bad_standing = rep(0,length(approved$loan_standing))
approved$bad_standing[approved$loan_standing=="Bad"]=1
# Interest rate is a character string x.xx% -- convert to numeric
approved$int_rate = as.numeric(gsub("%","",approved$int_rate))
# Use 'common sense' to pick a set of variables for inclusion
columnsToUse = c("id","loan_amnt","int_rate","installment",
                 "emp_length","annual_inc","home_ownership",
                 "purpose","dti",
                 "earliestCreditYr","avgFico","inq_last_6mths",
                 "mths_since_last_delinq","open_acc",
                 "mths_since_last_major_derog","bad_standing")
# Shuffle data and split into train and test sets - is this shuffled?  
training = approved[1:ceiling(nrow(approved)/3*2),columnsToUse]
validation = approved[-(1:ceiling(nrow(approved)/3*2)),columnsToUse]
# Do a logistic regression
reg1 = glm(bad_standing~. -id,data=training,family="binomial")
print(summary(reg1))

pred = predict(reg1,newdata=training,type="response")

pred1 = predict(reg1,newdata=validation,type="response")

summary(pred1)
mean(pred1-validation$bad_standing)
validation <- cbind(validation,pred1)
t.test(validation$pred1 ~ validation$bad_standing)


#stepwise regression process

#Create training sample of 500 good loans and 500 bad loans

bad <- subset(approved,bad_standing==1)
bad <- na.omit(bad[,columnsToUse])
badest <- sample(nrow(bad),500)
bad <- bad[badest,]

good <- subset(approved,bad_standing==0)
good <- na.omit(good[,columnsToUse])
goodest <- sample(nrow(good),500)
good <- good[goodest,]
est <- rbind(bad,good)

table(est$bad_standing)
badPop = mean(approved$bad_standing)
badSample=mean(est$bad_standing)

offset <- log(((1-badPop)/badPop)/((1-badSample)/badSample))
est$offset=offset

reg1 = glm(bad_standing ~ . -id,family=binomial,data=est,offset=offset)

sreg1 = glm(formula(reg1),data=est,offset=offset,family=binomial)
sreg2 = step(sreg1,data=est)

formula(sreg2)

sreg3 = glm(formula(sreg2),family=binomial,data=est,offset=offset)
summary(sreg3)

#See if this improves the prediction
#Need to create validation sample by removing est from approved (add back ID into est)
#Look at prediction scores that are 2x higher than the mean
#Maybe add in lateness to bad_standing?
validation <- approved[!(approved$id %in% est$id),]

pred1 = predict(sreg3,newdata=validation,type="response")

summary(pred1)
mean(pred1-validation$bad_standing)
validation <- cbind(validation,pred1)
t.test(validation$pred1 ~ validation$bad_standing)
validation <- validation[!is.na(validation$pred1),]

target <- validation[validation$pred1>4*mean(validation$pred1),]

mean(target$pred1)
mean(target$bad_standing)
