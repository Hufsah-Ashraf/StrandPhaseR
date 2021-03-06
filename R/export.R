#' Generates a bedgraph from GRanges object in order to upload on to UCSC Genome browser
#'
#' @param index is used to index the bedfile(s)
#' @param outputfolder Location to store created bedfile(s)
#' @param fragments A \code{\link{GRanges}} object with strand and mapq metadata, such as that generated by \code{\link{bam2GRanges}}

#' @author David Porubsky, Ashley Sanders
#' @export

exportBedGraph <- function(index, outputfolder, fragments=NULL, col="200,100,10") {

  ## Insert chromosome for in case it's missing
  insertchr <- function(gr) {
    mask <- which(!grepl('chr', seqnames(gr)))
    mcols(gr)$chromosome <- as.character(seqnames(gr))
    mcols(gr)$chromosome[mask] <- sub(pattern='^', replacement='chr', mcols(gr)$chromosome[mask])
    mcols(gr)$chromosome <- as.factor(mcols(gr)$chromosome)
    return(gr)
  }
  
  ## Write phased fragments to file
  if (!is.null(fragments)) {
    #get coverge values per genomic site
    rle.fragments.cov <- coverage(fragments)
    fragments.cov <- unlist( runValue(rle.fragments.cov), use.names = FALSE ) #get values of coverage per genomic site 
    fragments.cov.ranges <- unlist( ranges(rle.fragments.cov), use.names = FALSE ) #get genomic ranges with certain value of coverage 
    fragments <- GenomicRanges::GRanges(seqnames = seqlevels(fragments), ranges = fragments.cov.ranges, cov = fragments.cov)
    fragments <- insertchr(fragments)

    savefile.fragments <- file.path(outputfolder, paste0(index, '_phased.bed.gz'))
    savefile.fragments.gz <- gzfile(savefile.fragments, 'w')
    header <- paste('track type=bedGraph name=', index,'_reads description=BedGraph_of_phasedReads_',index, ' visibility=full color=',col, sep="")
    write.table(header, file=savefile.fragments.gz, row.names=FALSE, col.names=F, quote=FALSE, append=F, sep='\t')
    if (length(fragments)>0) {
      #bedG <- as.data.frame(fragments)[c('chromosome','start','end','cov')]
      bedG <- as(fragments, "data.frame")[c('chromosome','start','end','cov')]
    } else {
      bedG <- data.frame(chromosome='chr1', start=1, end=1, cov=NA)
    }
    write.table(bedG, file=savefile.fragments.gz, row.names=FALSE, col.names=F, quote=FALSE, append=T, sep='\t')
    close(savefile.fragments.gz)
  }
}  

  
#' Generates a VCF file from phased haplotypes
#'
#' @param index Unique identifier used to index analyzed individual/sample
#' @param outputfolder Location to store created VCF file(s)
#' @param phasedHap Data object containing phased haplotypes 
#' @param bsGenome A \code{BSgenome} object which contains reference genome usedto infer reference bases
#' @param chromosome Name of the chromosome for which we want to export vcf file

#' @import BSgenome

#' @author David Porubsky, Ashley Sanders
#' @export 
  
exportVCF <- function(index=NULL, outputfolder, phasedHap=NULL, bsGenome, chromosome=chr) {
  
  ## Print VCF header
  #savefile.vcf.gz <- gzfile(savefile.vcf, 'w')
  savefile.vcf <- file.path(outputfolder, paste0(chromosome, '_phased.vcf'))
  
  chr.len <- seqlengths(bsGenome)[seqnames(bsGenome) == chromosome]
  
  fileformat <- "##fileformat=VCFv4.2"
  date <- paste("##fileDate=",Sys.Date(),sep="")
  source.alg <- "##source=StrandPhase_algorithm"
  reference <- paste0("##reference=", attributes(bsGenome)$pkgname) 
  phasing <- "##phasing=Strand-seq"
  format1 <- "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">"
  format2 <- "##FORMAT=<ID=Q1,Number=1,Type=Float,Description=\"Quality measure of allele 1 (1-entropy)*coverage\">"
  format3 <- "##FORMAT=<ID=Q2,Number=1,Type=Float,Description=\"Quality measure of allele 2 (1-entropy)*coverage\">"
  format4 <- "##FORMAT=<ID=P1,Number=1,Type=Float,Description=\"Probability value of allele 1\">"
  format5 <- "##FORMAT=<ID=P2,Number=1,Type=Float,Description=\"Probability value of allele 2\">"
  contig <- paste0("##contig=<ID=",chromosome, ",length=",chr.len,">")
  cat(fileformat,date,source.alg,reference,phasing,format1,format2,format3,format4,format5,contig, sep = "\n", file=savefile.vcf, append=F)
  #cat("##contig=<ID=",chromosome, ",length=",chr.len,">", sep="", file=savefile.vcf, append=F)
  cat("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t", index, "\n", sep = "", file=savefile.vcf, append=T)
  
  if (!is.null(phasedHap)) {
    hap1.pos <- phasedHap$hap1.cons$pos
    hap2.pos <- phasedHap$hap2.cons$pos
    snv.pos <- sort(union(hap1.pos, hap2.pos))
    names(hap1.pos) <- as(phasedHap$hap1.cons$bases, "vector")
    names(hap2.pos) <- as(phasedHap$hap2.cons$bases, "vector")
    hap1.gap <- setdiff(snv.pos, hap1.pos)
    hap2.gap <- setdiff(snv.pos, hap2.pos)
    names(hap1.gap) <- rep("", length(hap1.gap))
    names(hap2.gap) <- rep("", length(hap2.gap))
    hap1.alleles <- names(sort(c(hap1.pos, hap1.gap)))
    hap2.alleles <- names(sort(c(hap2.pos, hap2.gap)))
    
    if (!grepl('chr', chromosome)) { chromosome <- sub(pattern='^', replacement='chr', chromosome) } #always add 'chr' if missing at the beginning of chromosome number
    snv.ranges <- GenomicRanges::GRanges(seqnames=chromosome, IRanges(start=snv.pos, end=snv.pos))
    ref.alleles <- Biostrings::Views(bsGenome, snv.ranges)
    ref.alleles <- as(ref.alleles, "DNAStringSet")
    ref.alleles <- as(ref.alleles, "vector")
    
    names(hap1.pos) <- (1-phasedHap$hap1.cons$ent) * phasedHap$hap1.cons$cov
    names(hap2.pos) <- (1-phasedHap$hap2.cons$ent) * phasedHap$hap2.cons$cov
    names(hap1.gap) <- rep(".", length(hap1.gap))
    names(hap2.gap) <- rep(".", length(hap2.gap))
    hap1.qual <- names(sort(c(hap1.pos, hap1.gap)))
    hap2.qual <- names(sort(c(hap2.pos, hap2.gap)))
    
    names(hap1.pos) <- phasedHap$hap1.cons$score
    names(hap2.pos) <- phasedHap$hap2.cons$score
    names(hap1.gap) <- rep(".", length(hap1.gap))
    names(hap2.gap) <- rep(".", length(hap2.gap))
    hap1.score <- names(sort(c(hap1.pos, hap1.gap)))
    hap2.score <- names(sort(c(hap2.pos, hap2.gap)))
    
    alt.alleles1 <- rep("", length(snv.pos))
    alt.alleles2 <- rep("", length(snv.pos))
    alt.alleles <- rep("", length(snv.pos))
    chr <- rep(chromosome, length(snv.pos))
    id <- rep(".", length(snv.pos))
    qual <- rep(".", length(snv.pos))
    filter <- rep(".", length(snv.pos))
    info <- rep(".", length(snv.pos))
    format <- rep("GT:Q1:Q2:P1:P2", length(snv.pos))
    
    alt.alleles1[ref.alleles != hap1.alleles & hap1.alleles != ""] <- hap1.alleles[ref.alleles != hap1.alleles & hap1.alleles != ""]
    alt.alleles2[ref.alleles != hap2.alleles & hap2.alleles != ""] <- hap2.alleles[ref.alleles != hap2.alleles & hap2.alleles != ""]
    
    hap1.alleles[alt.alleles2 == hap1.alleles & hap1.alleles != "" & alt.alleles1 != "" &  alt.alleles2 != "" & alt.alleles1 != alt.alleles2] <- 2
    hap2.alleles[alt.alleles2 == hap2.alleles & hap2.alleles != "" & alt.alleles1 != "" &  alt.alleles2 != "" & alt.alleles1 != alt.alleles2] <- 2
    hap1.alleles[ref.alleles == hap1.alleles] <- 0
    hap2.alleles[ref.alleles == hap2.alleles] <- 0
    hap1.alleles[alt.alleles1 == hap1.alleles & hap1.alleles != "" & alt.alleles1 != ""] <- 1
    hap1.alleles[alt.alleles2 == hap1.alleles & hap1.alleles != "" & alt.alleles2 != ""] <- 1
    hap2.alleles[alt.alleles1 == hap2.alleles & hap2.alleles != "" & alt.alleles1 != ""] <- 1
    hap2.alleles[alt.alleles2 == hap2.alleles & hap2.alleles != "" & alt.alleles2 != ""] <- 1
  
    hap1.alleles[hap1.alleles == ""] <- "."
    hap2.alleles[hap2.alleles == ""] <- "."
    phased.alleles <- paste(hap1.alleles, hap2.alleles, sep="|")
    
    genotypes <- paste(phased.alleles, hap1.qual, hap2.qual, hap1.score, hap2.score, sep=":")
    
    collapse.alt <- function(X,Y) {
      if (X==Y & X!="" & Y!="") {
        return(X)
      } else if (X!=Y & Y=="" & X!="") {
        return(X)
      } else if (X!=Y & Y!="" & X=="") {
        return(Y)
      } else if (X!=Y & Y!="" & X!="") {
        return(paste(X,Y, sep=","))
      } else {
        return("")
      }
    }
    
    alt.alleles <- mapply(collapse.alt, alt.alleles1, alt.alleles2, USE.NAMES = F)
    alt.alleles[alt.alleles == ""] <- "N"
    
    snv.pos <- as.integer(format(snv.pos, scientific = FALSE)) #make sure no float numbers in the output
    df <- data.frame(chr, snv.pos, id, ref.alleles, alt.alleles, qual, filter, info, format, genotypes, stringsAsFactors = FALSE)
    
    utils::write.table(df, file=savefile.vcf, row.names=FALSE, col.names=FALSE, quote=FALSE, append=TRUE, sep='\t')
  } 
}    
  
  
