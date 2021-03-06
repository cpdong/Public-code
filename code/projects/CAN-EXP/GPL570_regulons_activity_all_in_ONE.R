# RUN in pipelines
#GEOlist<- read.csv("https://raw.githubusercontent.com/cpdong/public/master/data/CAN-EXP/BRCA/BRCAlink.csv", header=T, stringsAsFactors=F)
#GEOlist<- GEOlist[which(GEOlist$platform=="GPL570"),]
#GPL570_list<- as.character(GEOlist[,1])

#for(m in 1:length(GPL570_list)){
    #############################################################
#    GSE_ID= GPL570_list[m]
#    platform= "GPL570"

#    dir="/home/cpdong/Desktop/regulonActivity/GPL570/"
    #############################################################
#    source("https://raw.githubusercontent.com/cpdong/public/master/code/projects/CAN-EXP/GPL570_regulons_activity_all_in_ONE.R")
#}
#
#
#
#
#
#
#
#
#
#
#
#
#
# get the top percentage of GRNBoost2 importance 
GRNBoost2_importance_percentage= 0.05
# Get the AUCell calculate percentage
AUCell_percentage=c(0.10, 0.15, 0.20, 0.25)
#
#
#
#
#
#
#
setwd(dir)

# get download link from github record file
dataLink<- read.csv("https://raw.githubusercontent.com/cpdong/public/master/data/CAN-EXP/BRCA/BRCAlink.csv", header=T, stringsAsFactors=F)
dlink<-dataLink[which(dataLink$Series == GSE_ID),]
dlink<-dlink[which(dlink$platform == platform),]
link<- dlink[,4]

source("https://raw.githubusercontent.com/cpdong/public/master/code/Extract_figshare_download_link.R")
library(data.table)
figlink<- download_link(link)
d1<- data.frame(fread(figlink), row.names=1)
# d1<- read.table(paste(filename), row.names=1, header=T,sep='\t', stringsAsFactors=F)

d2<- read.csv(paste("https://raw.githubusercontent.com/cpdong/public/master/data/CAN-EXP/", platform, "_ID_convert.csv", sep=''), header=T, stringsAsFactors=F)
# d3<- cbind(d2[, "gene_symbol"][match(rownames(d1), d2[,"gene_symbol"])], d1)
d3<- merge(d2, d1, by.x='Gene.Symbol', by.y='row.names', all.x=T)
d3<- d3[,-1]

# fileter row with 0 value as median
medianRows<- apply(d3[,-1], 1, median)
d3<- d3[which(! medianRows== 0),]

# filter row that show in ChIPBaseV2
d4<- read.csv(paste("https://raw.githubusercontent.com/cpdong/public/master/data/CAN-EXP/ChIPBaseV2_regNet_", platform, ".csv", sep=''), row.names=1, header=T, stringsAsFactors=F)

d5<- d3[which(d3$ENTREZ_GENE_ID %in% intersect(rownames(d4), d3$ENTREZ_GENE_ID)), ]
# for the next setp run AUCell analysis
d6<- data.frame(d5, row.names=1)
d5[,1]<- paste("G", d5[,1], sep='')

# write.csv(d5, paste(GSE_ID, "_feed2python.csv",sep=''), row.names=F, quote=F)
# generatge files for python run
write.csv(d4, "regNet_tf.csv", row.names=T, quote=F)
write.csv(d5, "feed2python.csv", row.names=F, quote=F)


# part 2: coexpression with GRNBoost2
#############################################################################
# make python scripts
# system(paste("directory=", dir,"\ # in system level
# sed -i 's|dir='/path/to/your/file'|dir='${directory}'|g' geo.py", sep=""))

# download from github
library("RCurl")
download.file("https://raw.githubusercontent.com/cpdong/public/master/code/projects/CAN-EXP/GRNBoost2_co-expression.py",destfile="GRNBoost2_co-expression.py",method="libcurl")

# make python scripts integrated into R scripts
system(paste("sed -i 's|dir='/path/to/your/file'|dir=\"",dir, "\"|g' GRNBoost2_co-expression.py", sep=""))

# run python scripts
system(paste("python ", dir, "GRNBoost2_co-expression.py", sep=''))
# end of python run

# part 3: calculate AUCell for patients
#############################################################################
matrix1<- as.matrix(d6)

overlapped_tfs<- intersect(rownames(matrix1), gsub('X', '', names(d4)))

# get spearman correlation to judge the positive or negative
# only left tfs correlation relations
corrMat <- cor(t(matrix1), method="spearman")
cor_tfs<- corrMat[, which(colnames(corrMat) %in% overlapped_tfs)]

# get result from GRNboost2
################################################################
network<- read.table(file = 'ex_GRNboost2_network.tsv', sep = '\t', header = F)
names(network)<- c("TF", "target", "importance")
# select n% of the important links
netGet<- network[1:round(GRNBoost2_importance_percentage* dim(network)[1]), ]
netGet[,1]<- gsub('G', '', netGet[,1])
netGet[,2]<- gsub('G', '', netGet[,2])
################################################################

library(AUCell)
library(GSEABase)

# d4=chipbase_net
# make genesets list for computing
# only left those with overlaped genes >= 20
geneSets<- GeneSet(c('g1'), setName='start')
list<- list(list())
for(i in 1:length(overlapped_tfs)){
    chipbase_links<- d4[,which(colnames(d4) == paste('X', overlapped_tfs[i],sep=''))]
    cor_tfs_spearman<- cor_tfs[,which(colnames(cor_tfs) == overlapped_tfs[i])]
	
    chipseq_tg<- rownames(d4)[which(chipbase_links ==1)]
    GRNboost2_tg<- netGet[which(netGet$TF ==paste(gsub('X', '', names(d4)[i]))),][,2]
    cor_tfs_positive_tg<- rownames(cor_tfs)[which(as.numeric(cor_tfs_spearman)>0)]
	
    hgnc_symbol<- as.character(d2[which(d2[,2] ==paste(gsub('X', '', names(d4)[i]))),][,1])	
    positve_regulons<- Reduce(intersect, list(chipseq_tg,GRNboost2_tg,cor_tfs_positive_tg))

    # we add TFs itself into the regulons #####################################
    # positve_regulons<- unique(c(paste(gsub('X', '', names(chipbase_net)[i])), positve_regulons))
	    
    if(length(positve_regulons)>=20){
        geneSets<- GeneSetCollection(c(geneSets, GeneSet(positve_regulons, setName=hgnc_symbol)))
    }
    else{
	geneSets<- geneSets
    }
}
geneSets<- geneSets[-1]

rankings <- AUCell_buildRankings(matrix1, nCores=4, plotStats=FALSE)
#
#
#
#
# decide the percenage of top importance for est AUCell
for(i in 1:length(AUCell_percentage)){
    AUCs <- AUCell_calcAUC(geneSets, rankings, aucMaxRank = ceiling(AUCell_percentage[i] * nrow(rankings)), verbose = TRUE)
    result<- getAUC(AUCs)

    write.csv(result, paste(GSE_ID, "_", platform, "_patients_regulon_activity_", AUCell_percentage[i], ".csv", sep=''), row.names=T, quote=F)
}
#
#
#
#
#
file.rename("ex_GRNboost2_network.tsv",  paste0(GSE_ID, "_", platform, "_GRNboost2_network.tsv", sep=''))
#
#
# remove temp files
fn <- c("GRNBoost2_co-expression.py", "feed2python.csv", "regNet_tf.csv", "dask-worker-space")
for(i in 1: length(fn)){
    # if (file.exists(fn[i])) file.remove(fn[i], recursive = TRUE)
	if (file.exists(fn[i])) unlink(fn[i], recursive = TRUE, force = TRUE)
}
#
#
# clear and release memory
rm(d1,d2,d3,d4,d5,d6,matrix1,overlapped_tfs, corrMat, cor_tfs,network, netGet,chipbase_links,cor_tfs_spearman,chipseq_tg,GRNboost2_tg,
   cor_tfs_positive_tg,hgnc_symbol,positve_regulons, geneSets, rankings, AUCs, result)
#
