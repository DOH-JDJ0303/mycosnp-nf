/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config ] // params.snpeffdb
if (params.skip_samples_file) { // check for skip_samples_file
    checkPathParamList.add(params.skip_samples_file)
}
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
sra_list = []
sra_ids = [:]
ch_input = null;
if (params.input) 
{ 
    ch_input = file(params.input) 
}
if(params.add_sra_file)
{
    sra_file = file(params.add_sra_file, checkIfExists: true)
    allLines  = sra_file.readLines()
    for( line : allLines ) 
    {
        row = line.split(',')
        if(row.size() > 1)
        {
            println "Add SRA ${row[1]} => ${row[0]}"
            sra_list.add(row[1])
            sra_ids[row[1]] = row[0]
        } else
        {
            if(row[0] != "")
            {
                println " ${row[0]} => ${row[0]}"
                sra_list.add(row[0])
                sra_ids[row[0]] = row[0]
            }
        }
    }
}

vcf_file_list = []
vcfidx_file_list = []
if(params.add_vcf_file)
{
    vcf_file = file(params.add_vcf_file, checkIfExists: true)
    allLines  = vcf_file.readLines()
    for( line : allLines ) 
    {
        if(line != "")
        {
            println " Add VCF => $line"
            t_vcf = file(line)
            t_idx = file(line + ".tbi")
            vcf_file_list.add(t_vcf)
            vcfidx_file_list.add(t_idx)
        }
    }
}

if(! ( params.input || params.add_sra_file || params.add_vcf_file ) ) { exit 1, 'Input samplesheet, sra file, or vcf file not specified!' }


/*
========================================================================================
    CONFIG FILES
========================================================================================
*/

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

/*
========================================================================================
    IMPORT LOCAL MODULES/SUBWORKFLOWS
========================================================================================
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { SRA_FASTQ_SRATOOLS       } from '../subworkflows/local/sra_fastq_sratools'
include { INPUT_CHECK              } from '../subworkflows/local/input_check'
include { SEQKIT_PAIR              } from '../modules/nf-core/modules/seqkit/pair/main'
include { FAQCS                    } from '../modules/nf-core/modules/faqcs/main'
include { GAMBIT_QUERY             } from '../modules/local/gambit'
include { SUBTYPE                  } from '../modules/local/subtype'
include { PRE_MYCOSNP_INDV_SUMMARY } from '../modules/local/pre_mycosnp_indv_summary'
include { PRE_MYCOSNP_COMB_SUMMARY } from '../modules/local/pre_mycosnp_comb_summary'
/*
========================================================================================
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
========================================================================================
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQC as FASTQC_RAW        } from '../modules/nf-core/modules/fastqc/main'
include { SPADES as SPADES            } from '../modules/nf-core/modules/spades/main'
include { SEQTK_SEQ as SEQTK_SEQ      } from '../modules/nf-core/modules/seqtk/seq/main'
include { MULTIQC                     } from '../modules/nf-core/modules/multiqc/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/modules/custom/dumpsoftwareversions/main'


/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

// Info required for completion email and summary
def multiqc_report = []


workflow PRE_MYCOSNP_WF {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    ch_all_reads = Channel.empty()
    ch_sra_reads = Channel.empty()
    ch_sra_list  = Channel.empty()
    if(params.add_sra_file)
    {   
        ch_sra_list = Channel.fromList(sra_list)
                             .map{valid -> [ ['id':sra_ids[valid],single_end:false], valid ]}
        SRA_FASTQ_SRATOOLS(ch_sra_list)
        ch_all_reads = ch_all_reads.mix(SRA_FASTQ_SRATOOLS.out.reads)
    }
    
    if(params.input)
    {
        INPUT_CHECK (
            ch_input
        )
        ch_all_reads = ch_all_reads.mix(INPUT_CHECK.out.reads)
        ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)
    }

    // Copy reads to bucket for NCBI upload
    if(params.ncbi_bucket){
        println("Copying reads to bucket for NCBI uploads:")
        def ncbi_bucket_path = file(params.ncbi_bucket)
        INPUT_CHECK.out.reads.map{ meta, reads -> [reads.get(0).copyTo(ncbi_bucket_path.resolve(meta.id+"_R1.fastq.gz")), reads.get(1).copyTo(ncbi_bucket_path.resolve(meta.id+"_R2.fastq.gz"))] }.view()
    }

    //
    // MODULE: Run Pre-FastQC 
    //
    FASTQC_RAW (
        ch_all_reads
    )
    ch_versions = ch_versions.mix(FASTQC_RAW.out.versions.first())

    //
    // MODULE: Run seqkit to remove unpaired reads
    //
    SEQKIT_PAIR(
        ch_all_reads
    )
    ch_versions = ch_versions.mix(SEQKIT_PAIR.out.versions.first())

    //
    // MODULE: Run FAQCs - no downsampling option because a reference cannot be supplied before knowing the species
    //
    FAQCS(
        SEQKIT_PAIR.out.reads
    )
    ch_versions = ch_versions.mix(FAQCS.out.versions.first())

    //
    // MODULE: Run SPAdes
    //
    FAQCS.out.reads.map{ meta, illumina -> [meta, illumina, [], []] }.set{ ch_trmd_reads }
    SPADES (
        ch_trmd_reads,
        [],
        []
    )
    ch_versions = ch_versions.mix(SPADES.out.versions.first())

    //
    // MODULE: Run seqtk seq to remove small contigs
    //

    SEQTK_SEQ(
        SPADES.out.scaffolds
    )
    ch_versions = ch_versions.mix(SEQTK_SEQ.out.versions.first())

    //
    // MODULE: Run Gambit
    //
    GAMBIT_QUERY(
        SEQTK_SEQ.out.fastx,
        params.gambit_db,
        params.gambit_h5
    )
    ch_versions = ch_versions.mix(GAMBIT_QUERY.out.versions.first())

    //
    // MODULE: Subtype
    //

    // Join the GAMBIT output and the spades assembly into a single channel   
    SEQTK_SEQ.out.fastx.map{ meta, scaffolds -> [meta, scaffolds] }.set{ ch_scaffolds }
    GAMBIT_QUERY.out.taxa.map{ meta, gambit -> [meta, gambit] }.join(ch_scaffolds).set{ ch_gambit_assembly }

    // Define path to subtyper files
    SUBTYPE(
        ch_gambit_assembly,
        params.subtype_db
    )

    //
    // MODULE: Create line summary for each sample
    //

    // Combine trimmed reads and the QC reference into single channel
    FAQCS.out.txt.map{ meta, txt -> [meta, txt] }.set{ ch_faqcs_txt }
    GAMBIT_QUERY.out.taxa.map{ meta, gambit -> [meta, gambit] }.set{ ch_gambit }
    SUBTYPE.out.subtype.map{ meta, subtype -> [meta, subtype] }.set{ ch_subtype }
    SEQTK_SEQ.out.fastx.map{ meta, scaffolds -> [meta, scaffolds] }.join(ch_faqcs_txt).join(ch_gambit).join(ch_subtype).set{ ch_line_summary_input }

    PRE_MYCOSNP_INDV_SUMMARY(
        ch_line_summary_input
    )

    //
    // MODULE: Combine line summaries into single output
    //
    PRE_MYCOSNP_COMB_SUMMARY(
        PRE_MYCOSNP_INDV_SUMMARY.out.result.map{ meta, result -> [result] }.collect()
    )

    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowMycosnp.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_config))
    ch_multiqc_files = ch_multiqc_files.mix(ch_multiqc_custom_config.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC_RAW.out.zip.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect()
    )
    multiqc_report = MULTIQC.out.report.toList()
    ch_versions    = ch_versions.mix(MULTIQC.out.versions)
}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
}

/*
========================================================================================
    THE END
========================================================================================
*/
