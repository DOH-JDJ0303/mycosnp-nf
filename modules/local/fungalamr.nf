process FUNGALAMR {
    tag "$meta.id"
    label 'process_low'

    container "public.ecr.aws/o8h2f0o1/allelefreq:1.2"

    input:
    tuple val(meta), path(reads)
    path db

    output:
    tuple val(meta), path("mutations.csv"), emit: mutations
    // path "versions.yml", emit: versions

    script:
    """
    fungalAMR \\
        --db ${db} \\
        --r1 ${reads[0]} \\
        --r2 ${reads[1]} \\
        --outdir ./
    """
}