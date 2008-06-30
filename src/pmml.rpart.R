# PMML: Predictive Modelling Markup Language
#
# Part of the Rattle package for Data Mining
#
# Time-stamp: <2008-06-21 15:48:59 Graham Williams>
#
# Copyright (c) 2008 Togaware Pty Ltd
#
# This files is part of the Rattle suite for Data Mining in R.
#
# Rattle is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Rattle is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Rattle. If not, see <http://www.gnu.org/licenses/>.

########################################################################
# rpart PMML exporter
#
# Original: by Togaware
# 
# Updated: updated regression tree, 
#          added ScoreDistribution, missingValueStrategy 
#          by Zementis, Inc. in June 2008
#           
#######################################################################
pmml.rpart <- function(model,
                       model.name="RPart_Model",
                       app.name="Rattle/PMML",
                       description="RPart decision tree model",
                       copyright=NULL, ...)
{
  if (! inherits(model, "rpart"))
    stop("Not a legitimate rpart object")

  functionName <- "classification"
  if (model$method != "class") functionName <- "regression"
  
  require(XML, quietly=TRUE)
  require(rpart, quietly=TRUE)
  
  # Collect the required information. We list all variables,
  # irrespective of whether they appear in the final model. This
  # seems to be the standard thing to do with PMML. It also adds
  # extra information - i.e., the model did not need these extra
  # variables!

  field <- NULL
  field$name <- as.character(attr(model$terms, "variables"))[-1]
  number.of.fields <- length(field$name)
  field$class <- attr(model$terms, "dataClasses")
  target <- field$name[1]

  for (i in 1:number.of.fields)
  {
    if (field$class[[field$name[i]]] == "factor")
      if (field$name[i] == target)
        field$levels[[field$name[i]]] <- attr(model, "ylevels")
      else
        field$levels[[field$name[i]]] <- attr(model,"xlevels")[[field$name[i]]]
  }

  # Start to create the PMML object

  pmml <- pmmlRootNode("3.2")

  # PMML -> Header

  pmml <- append.XMLNode(pmml, pmmlHeader(description, copyright, app.name))

  # PMML -> DataDictionary

  pmml <- append.XMLNode(pmml, pmmlDataDictionary(field))

  # PMML -> TreeModel

  tree.model <- xmlNode("TreeModel", attrs=c(modelName=model.name,
                                       functionName=functionName,
                                       algorithmName="rpart",
                                       splitCharacteristic="binarySplit",
                                       missingValueStrategy="defaultChild"))

  # PMML -> TreeModel -> MiningSchema
  
  tree.model <- append.XMLNode(tree.model, pmmlMiningSchema(field, target))

  # PMML -> TreeModel -> Node

  # Collect information to create nodes.
  
  depth <- rpart:::tree.depth(as.numeric(row.names(model$frame)))
  count <- model$frame$n
  label <- labels(model, pretty=0, digits=7)
  field <- label[1]
  operator <- ""
  value <- "" #list("")

  # Added by Zementis: Information to create nodes.
  ff <- model$frame
  cp <- 0
  id <- as.integer(row.names(ff))
  parent.id <- ifelse(id==1,1, floor(id/2))
  parent.cp <- ff$complexity[match(parent.id, id)]
  rows <- (1:length(id))[parent.cp > cp]
  parent_ii <- 1

  # Check the functionName.
  
  score <- attr(model, "ylevels")[model$frame$yval]
  if(functionName == "regression") score <- ff$yval[rows]

  # Get the information for the primary predicates

  for (i in 2:length(label))
  {
    field <-  c(field, strsplit(label[i], '>|<|=')[[1]][1])
    op <- substr(label[i], nchar(field[i])+1, nchar(field[i])+2)
    if (op == ">=")
    {
      operator <- c(operator, "greaterOrEqual")
      value <- c(value, substr(label[i], nchar(field[i])+3, nchar(label[i])))
    }
    else if (op == "< ")
    {
      operator <- c(operator, "lessThan")
      value <- c(value, substr(label[i], nchar(field[i])+3, nchar(label[i])))
    }
    else if (substr(op, 1, 1) == "=")
    {
      operator <- c(operator, "isIn")
      value <- c(value, substr(label[i], nchar(field[i])+2, nchar(label[i])))
    }
  }

  node <- genBinaryTreeNodes(depth, id, count, score, field, operator, value ,
                             model, parent_ii, rows,"right")

  tree.model <- append.XMLNode(tree.model, node)

  # Add to the top level structure.

  pmml <- append.XMLNode(pmml, tree.model)

  return(pmml)
}

############################################################################
# FUNCTION: getBinaryTreeNodes
#
# Goal: create nodes for the tree (a recursive function)

genBinaryTreeNodes <- function(depths, ids, counts, scores, fields,
                               ops, values,model, parent_ii, rows,position)
{
  depth <- depths[1]
  count <- counts[1]
  score <- scores[1]
  field <- fields[1]
  op <- ops[1]
  value <- values[1]

  # Added by zementis

  ff <- model$frame
  id <- ids[1]
  ii <- rows[1]

  # Assign the default child for non-leaf nodes.
  
  if(length(ids) > 1)  # Non-leaf node
  {
    sons <- 2*id + c(0,1)
    sons.n <- ff$n[match(sons, ids)]

    childId = sons[2]
    if(sons.n[1] >= sons.n[2]) childId = sons[1]
 
    node <- xmlNode("Node", attrs=c(id=id, score=score, recordCount=count,
                              defaultChild=childId))
  }
  else  # Leaf node
  {
    node <- xmlNode("Node", attrs=c(id=id,score=score, recordCount=count))
  }

  # Create the predicate for the node

  if (field == "root")
  {
    predicate <- xmlNode("True")
  }
  else if (ff$nsurrogate[parent_ii] >0)  # When the node has surrogate predicates
  {  
    predicate <-  xmlNode("CompoundPredicate",attrs=c(booleanOperator = "surrogate"))

    # Add the primary predicate
    
    predicate <- append.XMLNode(predicate,getPrimaryPredicates(field,op,value))

    # Add the surrogate predicates
    
    predicate <- getSurrogatePredicates(predicate, ff, model$splits, parent_ii, position)
  }
  else # When the node does not have surrogate predicates
  {
     # Add the primary predicate
    
     predicate <- getPrimaryPredicates(field, op, value)
  }
  node <- append.XMLNode(node, predicate) 

  # Add score distribution for classification case.
  
  if(model$method == "class")
  {
    ylevel <- attr(model,'ylevels')
    node <- getScoreDistributions(node, ylevel, ff, ii)
  }

  # The recursive function to create child nodes.
  
  if (length(depths) == 1)
  {
    left <- NULL
    right <- NULL
  }
  else
  {
    split.point <- which(depths[c(-1,-2)] == depths[2]) + 1 # Binary tree
    lb <- 2:split.point
    rb <- (split.point + 1):length(depths)
    left <- genBinaryTreeNodes(depths[lb], ids[lb], counts[lb], scores[lb], fields[lb],
                               ops[lb], values[lb], model, ii, rows[lb], "left")
    right <- genBinaryTreeNodes(depths[rb], ids[rb],counts[rb], scores[rb], fields[rb],
                                ops[rb], values[rb], model, ii, rows[rb], "right")  
  }
 
  if (!is.null(left))
  {
    node <- append.XMLNode(node, left)
    node <- append.XMLNode(node, right)
  }

  return(node)
}

#############################################################################
# FUNCTION: getPrimaryPredicates
#
# Goal: add the primary predicate for the node

getPrimaryPredicates <- function(field,op,value)
{
  if (op %in% c("greaterOrEqual", "lessThan"))
  {
    predicate <- xmlNode("SimplePredicate",
                         attrs=c(field=field, operator=op, value=value))
  }
  else if (op == "isIn")
  {
    predicate <- getSimpleSetPredicate(field,op,value)
  }

  return(predicate)
}

##############################################################################
# function: getSurrogatePredicates
#
# goal: add the surrogate predicates to take care of the missing value cases
#
# author: Zementis, Inc.
#
# date: June, 2008
##############################################################################
getSurrogatePredicates <- function(predicate,ff,splits,i,position)
{
    is.leaf <- (ff$var=='<leaf>')
    index <- cumsum(c(1, ff$ncompete + ff$nsurrogate + 1*(!is.leaf)))

    # j: indices of the surrogate predicates in the splits (list) for the current node
    j <- seq(1 +index[i] + ff$ncompete[i], length.out=ff$nsurrogate[i])

    predicateNameList <- dimnames(splits)[[1]]
    predicateSignList <- splits[,2]
    predicateValueList <- splits[,4]

    # n: number of surrogate predicates in the current node
    n<- length(predicateNameList[j])
    currentNodePredicateNameList <- predicateNameList[j]
    currentNodeSignList <- predicateSignList[j]
    currentNodeValueList <- predicateValueList[j]

    for (k in 1:n)
    { 
       if(position == "left") {
          op <- "lessThan"
          if(currentNodeSignList[[k]]>=0)
          { 
             op <- "greaterOrEqual"
          }
       } else {
          op <- "greaterOrEqual"
          if(currentNodeSignList[[k]]>=0)
          {
             op <- "lessThan"
          }
       }

       predicate<- append.XMLNode(predicate,xmlNode("SimplePredicate",attrs=c(field=currentNodePredicateNameList[k], operator=op,
                                  value=currentNodeValueList[[k]])))
    }
    return(predicate)
}

########################################################################
# Function: getSimpleSetPredicate
#
# Goal: refator the original code, which creates the simple set predicate
# 
# Original by: togaware
#
# Refactored by: Zementis, Inc.
#
# Refactored date: June, 2008

getSimpleSetPredicate <- function(field, op, value)
{
  predicate <- xmlNode("SimpleSetPredicate", attrs=c(field=field, booleanOperator=op))
  value <- strsplit(value[[1]], ",")[[1]]

  # Do we need quotes around the values?
  # vals <- paste('"', value, '"', collapse=" ", sep="")

  vals <- paste(value, collapse=" ", sep="")

  predicate <- append.XMLNode(predicate, xmlNode("Array", vals,
                                                 attrs=c(n=length(value),
                                                   type="string")))

  return(predicate)
}

#######################################################################
# function: getScoreDistributions
#
# goal: extract the probability for each category (only for classification case)
#
# author: Zementis, Inc.
#
# date: June, 2008
#######################################################################
getScoreDistributions <- function(node, ylevel, ff, ii)
{
   # ii: the sequential oreder of the current node

   # n: number of classification categories
   n = length(ylevel)
   recordCountMap <- ff$yval2[ii,2:(1+n) ,drop=TRUE]
   confidenceMap <- ff$yval2[ii,(n+2):(2*n+1) ,drop=TRUE]

   for(i in 1:n) 
   {
     scoreDist <- xmlNode("ScoreDistribution", attrs = c(value=ylevel[i], recordCount = recordCountMap[i], confidence = confidenceMap[i]))
     node <- append.XMLNode(node,scoreDist)
   }

   return(node)
}

pmml.rpart.as.rules <- function(model,
                                model.name="RPart_Model",
                                app.name="RPart",
                                description="RPart model as rules",
                                copyright=NULL)
{
  require(XML, quietly=TRUE)
  require(rpart, quietly=TRUE)
  
  if (! inherits(model, "rpart")) stop("Not a legitimate rpart tree")

  # Collect the required information

  field <- NULL
  field$name <- as.character(attr(model$terms, "variables"))[-1]
  number.of.fields <- length(field$name)
  field$class <- attr(model$terms, "dataClasses")
  target <- field$name[1]

  for (i in 1:number.of.fields)
  {
    if (field$class[[field$name[i]]] == "factor")
      if (field$name[i] == target)
        field$levels[[field$name[i]]] <- attr(model, "ylevels")
      else
        field$levels[[field$name[i]]] <- attr(model,"xlevels")[[field$name[i]]]
  }

  # PMML
  
  pmml <- pmmlRootNode("3.2")

  # PMML -> Header

  pmml <- append.XMLNode(pmml, pmmlHeader(description, copyright, app.name))
  
  # PMML -> DataDictionary
  
  pmml <- append.XMLNode(pmml, pmmlDataDictionary(field))

  # PMML -> RuleSetModel
  
  tree.model <- xmlNode("RuleSetModel",
                        attrs=c(modelName=model.name,
                          functionName="classification",
                          splitCharacteristic="binary",
                          algorithmName="rpart"))

  # MiningSchema
  
  tree.model <- append.XMLNode(tree.model, pmmlMiningSchema(field, target))

  # Add in actual tree nodes.

  rule.set <- xmlNode("RuleSet")
  rule.set <- append.XMLNode(rule.set,
                             xmlNode("RuleSelectionMethod",
                                     attrs=c(criterion="firstHit")))
  
  # Visit each leaf node to generate a rule.

  ordered <- rev(sort(model$frame$yval2[,5], index=TRUE)$ix)
  names <- row.names(model$frame)
  next.child <- 2
  for (i in ordered)
  {
    if (model$frame[i,1] == "<leaf>")
    {
      simple.rule <- xmlNode("SimpleRule",
                             attrs=c(id=sprintf("R%03d", as.integer(names[i])),
                               recordCount=model$frame[i,]$n))
      pth <- path.rpart(model, nodes=as.numeric(names[i]), print.it=FALSE)
      pth <- unlist(pth)[-1]
      if (length(pth) != 0)
      {
        predicate <- xmlNode("CompoundPredicate",
                             attrs=c(booleanOperator="and"))
        for (p in (1:length(pth)))
        {
          f <- unlist(strsplit(pth[p], "<|>=|="))[[1]]
          o <- ifelse(length(grep("<", pth[p]))>0, "lessThen",
               ifelse(length(grep(">=", pth[p]))>0, "greaterOrEqual",
               ifelse(length(grep("=", pth[p]))>0, "equal", "DONTKNOW")))
          v <- unlist(strsplit(pth[p], "<|>=|="))[[2]]
          predicate$children[[p]] <- xmlNode("SimplePredicate",
                                             attrs=c(field=f,
                                               operator=o,
                                               value=v))
        }
      }
      simple.rule$children[[1]] <- predicate
      rule.set$children[[next.child]] <- simple.rule
      next.child <- next.child + 1
    }
  }

  tree.model <- append.XMLNode(tree.model, rule.set)
  
  # Add to the top level structure.
  
  pmml <- append.XMLNode(pmml, tree.model)
  
  return(pmml)
}
