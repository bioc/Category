## setMethod("pvalues", "ChrMapHyperGResult",
##           function(r) {
##               unlist(nodeData(r@chrGraph, attr="pvalue"))
##           })

## setMethod("universeMappedCount", "ChrMapHyperGResult",
##           function(r) {
##               u <- unlist(nodeData(r@chrGraph, attr="geneIds"))
##               length(unique(u))
##           })
setMethod("chrGraph", signature(r="ChrMapHyperGResult"),
          function(r) r@chrGraph)


setMethod("pvalues", signature(r="ChrMapHyperGResult"),
          function(r) {
              unlist(nodeData(r@chrGraph, attr="pvalue"))[r@pvalue.order]
              })


setMethod("oddsRatios", signature(r="ChrMapHyperGResult"),
          function(r) {
              unlist(nodeData(r@chrGraph, attr="oddsRatio"))[r@pvalue.order]
              })


setMethod("expectedCounts", signature(r="ChrMapHyperGResult"),
          function(r) {
              unlist(nodeData(r@chrGraph, attr="expCount"))[r@pvalue.order]
              })


entrezGeneUniverse <- function(r) {
    nodeData(r@chrGraph, n=nodes(r@chrGraph)[r@pvalue.order],
             attr="geneIds")
}


setMethod("geneIdUniverse", signature(r="ChrMapHyperGResult"),
          function(r) {
              entrezGeneUniverse(r)
          })


setMethod("condGeneIdUniverse", signature(r="ChrMapHyperGResult"),
          function(r) {
              if (isConditional(r))
                nodeData(r@chrGraph, n=nodes(r@chrGraph)[r@pvalue.order],
                         attr="condGeneIds")
              else
                geneIdUniverse(r)
          })


setMethod("geneCounts", signature(r="ChrMapHyperGResult"),
          function(r) {
              sapply(condGeneIdUniverse(r), function(x) {
                  sum(r@geneIds %in% x)
              })
          })


## setMethod("condGeneCounts", signature(r="ChrMapHyperGResult"),
##           function(r) {
##               sapply(condGeneIdUniverse(r), function(x) {
##                   sum(r@geneIds %in% x)
##               })
##           })


setMethod("universeCounts", signature(r="ChrMapHyperGResult"),
          function(r) {
              sapply(entrezGeneUniverse(r), length)
          })


setMethod("universeMappedCount", signature(r="ChrMapHyperGResult"),
          function(r) {
              length(unique(unlist(entrezGeneUniverse(r))))
          })


setMethod("isConditional", signature(r="ChrMapHyperGResult"),
          function(r) r@conditional)


setMethod("description", signature(object="ChrMapHyperGResult"),
          function(object) {
              cond <- "Conditional"
              if (!isConditional(object))
                cond <- ""
              desc <- paste("Gene to %s", cond, "test for %s-representation")
              desc <- sprintf(desc,
                              paste(testName(object), collapse=" "),
                              testDirection(object))
              desc
          })


selectedGenes <- function(r, id) {
    ## FIXME: make me a method!
    ans <- geneIdUniverse(r)[id]
    ans <- lapply(ans, intersect, geneIds(r))
    ans
}


sigCategories <- function(res, p) {
    ## FIXME: make me a method!
    if (missing(p))
      p <- pvalueCutoff(res)
    pv <- pvalues(res)
    goIds <- names(pv[pv < p])
    goIds
}


inducedTermGraph <- function(r, id, children=TRUE, parents=TRUE,
                             ...) {
    if (!children && !parents)
      stop("children and parents can't both be FALSE")
    ## XXX: should use more structure here
    goName <- paste(testName(r), collapse="")
    goKidsEnv <- get(paste(goName, "CHILDREN", sep=""))
    goParentsEnv <- get(paste(goName, "PARENTS", sep=""))
    goIds <- character(0)

    wantedNodes <- id
    ## children
    if (children) {
        wantedNodes <- c(wantedNodes,
                         unlist(edges(chrGraph(r))[id], use.names=FALSE))
    }
    ## parents
    g <- reverseEdgeDirections(chrGraph(r))
    if (parents) {
        wantedNodes <- c(wantedNodes,
                         unlist(edges(g)[id], use.names=FALSE))
    }
    wantedNodes <- unique(wantedNodes)
    g <- subGraph(wantedNodes, g)

    ## expand
    if (children) {
        for (goid in id) {
            kids <- unique(goKidsEnv[[goid]])
            for (k in kids) {
                if (!(k %in% nodes(g))) {
                    g <- addNode(k, g)
                    g <- addEdge(k, goid, g)
                }
            }
        }
    }
    if (parents) {
        for (goid in id) {
            elders <- unique(goKidsEnv[[goid]])
            for (p in elders) {
                if (!(p %in% nodes(g))) {
                    g <- addNode(p, g)
                    g <- addEdge(goid, p, g)
                }
            }
        }
    }
    g
}


## FIXME: perhpas it doesn't make sense to exclude the untestable GO terms.
## maybe it would be better to keep them in as it will be less confusing?
plotGOTermGraph <- function(g, r=NULL, add.counts=TRUE,
                            max.nchar=20,
                            node.colors=c(sig="lightgray", not="white"),
                            ...) {
    n <- nodes(g)
    termLab <- substr(sapply(mget(n, GOTERM), Term), 0, max.nchar)
    ncolors <- rep("red", length(n))
    if (!is.null(r) && add.counts) {
        if (is.null(names(node.colors)) ||
            !all(c("sig", "not") %in% names(node.colors)))
          stop(paste("invalid node.colors arg:",
                     "must have named elements 'sig' and 'not'"))
        resultTerms <- names(pvalues(r))
        ncolors <- ifelse(n %in% sigCategories(r), node.colors["sig"],
                          node.colors["not"])
        counts <- sapply(n, function(x) {
            if (x %in% resultTerms) {
                paste(geneCounts(r)[x], "/",
                      universeCounts(r)[x],
                      sep="")
            } else {
                "0/??"
            }
        })
        nlab <- paste(termLab, counts)
    } else {
        nlab <- termLab
    }
    nattr <- makeNodeAttrs(g,
                           label=nlab,
                           shape="ellipse",
                           fillcolor=ncolors,
                           fixedsize=FALSE)
    plot(g, ..., nodeAttrs=nattr)
}


termGraphs <- function(r, id=NULL, pvalue=NULL, use.terms=TRUE) {
    if (!is.null(id) && !is.null(pvalue))
      warning("ignoring pvalue arg since GO IDs where specified")
    if (missing(pvalue) || is.null(pvalue))
      pvalue <- pvalueCutoff(r)
    if (is.null(id))
      goids <- sigCategories(r, pvalue)
    else
      goids <- id
    g <-  reverseEdgeDirections(subGraph(goids, chrGraph(r)))
    cc <- connectedComp(g)
    sapply(cc, subGraph, g)
}
