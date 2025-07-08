def call(Map params) {
    def runJobId = ""

    node {
        def SSH_USER    = params.sshUser
        def IMAGE       = params.image
        def SCRATCH_DIR = params.scratchDir
        def LOG_DIR     = params.logDir
        def SIF_PATH    = "${SCRATCH_DIR}/images/${IMAGE}.sif"
        def OVERLAY_PATH= "${SCRATCH_DIR}/${IMAGE}.ext3"
        def TMP_DIR     = "${SCRATCH_DIR}/tmp"
        def DOCKER_URL  = params.dockerUrl
        def SCRIPT_BASE_URL = 'https://raw.githubusercontent.com/thewillyP/jenkins/main/library'
        def BUILD_JOB_ID = ""

        stage('Detect Hostname') {
            SSH_USER = SSH_USER // to prevent unused warning
            IMAGE = IMAGE
            LOG_DIR = LOG_DIR
            def EXEC_HOST = sh(script: "hostname", returnStdout: true).trim()
            echo "Executor host: ${EXEC_HOST}"

            stage('Cancel Existing Jobs') {
                sh """
                ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'curl -fsSL ${SCRIPT_BASE_URL}/cancel_jobs.sh | bash -s ${SSH_USER} ${IMAGE}'
                """
            }

            stage('Build Image If Needed') {
                def imageExists = sh(
                    script: "ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} '[ -f ${SIF_PATH} ] && echo exists || echo missing'",
                    returnStdout: true
                ).trim()

                if (params.forceRebuild || imageExists == "missing") {
                    def buildOut = sh(
                        script: """
                        ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                        'curl -fsSL ${SCRIPT_BASE_URL}/build_image.sh | bash -s \\
                        "${SCRATCH_DIR}" "${OVERLAY_PATH}" "${SIF_PATH}" "${DOCKER_URL}" "${LOG_DIR}" "${IMAGE}" \\
                        "${params.buildMem}" "${params.buildCPUs}" "${params.overlaySrc}" "${params.buildTime}"'
                        """,
                        returnStdout: true
                    ).trim()

                    BUILD_JOB_ID = (buildOut =~ /Submitted batch job (\d+)/)?.getAt(0)?.getAt(1) ?: ""
                    echo "Build job submitted with ID: ${BUILD_JOB_ID}"
                } else {
                    BUILD_JOB_ID = ""
                }
            }

            stage('Create TMP Directory') {
                sh """
                ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'mkdir -p ${TMP_DIR}'
                """
            }

            stage('Submit Run Job') {
                def binds = params.binds ?: ""
                def useGpu = params.useGpu ? "true" : "false"

                def runOut = sh(
                    script: """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                    'curl -fsSL ${SCRIPT_BASE_URL}/run_job.sh | bash -s \\
                    "${LOG_DIR}" "${SIF_PATH}" "${OVERLAY_PATH}" "${SSH_USER}" "${BUILD_JOB_ID}" \\
                    "${params.runMem}" "${params.runCPUs}" "${params.runTime}" "${IMAGE}" "${TMP_DIR}" \\
                    "${binds}" "${params.entrypointUrl}" "${useGpu}"'
                    """,
                    returnStdout: true
                ).trim()

                runJobId = (runOut =~ /Submitted batch job (\d+)/)?.getAt(0)?.getAt(1) ?: ""
                echo "Run job submitted with ID: ${runJobId}"
            }
        }
    }

    return runJobId
}