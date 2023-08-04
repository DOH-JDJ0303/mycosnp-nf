/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowMycosnp.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.fasta ] // params.snpeffdb
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
include { SRA_FASTQ_SRATOOLS } from '../subworkflows/local/sra_fastq_sratools'
include { INPUT_CHECK        } from '../subworkflows/local/input_check'
/*
========================================================================================
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
========================================================================================
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQC as FASTQC_RAW        } from '../modules/nf-core/modules/fastqc/main'
include { FASTP as FASTP              } from '../modules/nf-core/modules/fastp/main'
include { SPADES as SPADES            } from '../modules/nf-core/modules/spades/main'
include { MULTIQC                     } from '../modules/nf-core/modules/multiqc/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/modules/custom/dumpsoftwareversions/main'


/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

// Info required for completion email and summary
def multiqc_report = []


workflow CLASSIFY {

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


    //
    // MODULE: Run Fastp
    //
    ch_fastp_adapter = Channel.empty()
    FASTP (
        ch_all_reads,
        ch_fastp_adapter,
        true,
        true

    )
    ch_versions = ch_versions.mix(FASTP.out.versions.first())

    //
    // MODULE: Run SPAdes
    //
    ch_spades_yml = Channel.empty()
    ch_spades_hmm = Channel.empty()
    SPADES (
        FASTP.out.reads,
        ch_spades_yml,
        ch_spades_hmm
    )
    ch_versions = ch_versions.mix(SPADES.out.versions.first())

     CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: Run Pre-FastQC 
    //
    FASTQC_RAW (
        ch_all_reads
    )
    ch_versions = ch_versions.mix(FASTQC_RAW.out.versions.first())

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
