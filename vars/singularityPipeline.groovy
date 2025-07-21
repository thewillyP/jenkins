def call(Map params) {
    def runJobId = ""
    node {
        def SSH_USER    = params.sshUser
        def IMAGE       = params.image
        def SCRATCH_DIR = params.scratchDir
        def LOG_DIR     = params.logDir
        def SIF_PATH    = "${SCRATCH_DIR}/images/${IMAGE}.sif"
        def OVERLAY_PATH= "${SCRATCH_DIR}/${IMAGE}.ext3"
        def TMP_DIR     = "${SCRATCH_DIR}/tmp_${IMAGE}"
        def DOCKER_URL  = params.dockerUrl
        def BUILD_JOB_ID = ""
        def EXEC_HOST = params.execHost
        echo "Executor host: ${EXEC_HOST}"
        stage('Checkout Scripts') {
            checkout([
                $class: 'GitSCM',
                branches: [[name: '*/main']],
                userRemoteConfigs: [[url: 'https://github.com/thewillyP/jenkins.git']]
            ])
        }
        stage('Cancel Existing Jobs') {
            sh """
            ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} '
                bash -s "${SSH_USER}" "${IMAGE}"
            ' < library/cancel_jobs.sh
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
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} '
                        bash -s "${SCRATCH_DIR}" "${OVERLAY_PATH}" "${SIF_PATH}" "${DOCKER_URL}" "${LOG_DIR}" "${IMAGE}" \\
                                "${params.buildMem}" "${params.buildCPUs}" "${params.overlaySrc}" "${params.buildTime}"
                    ' < library/build_image.sh
                    """,
                    returnStdout: true
                ).trim()
                BUILD_JOB_ID = (buildOut =~ /Submitted batch job (\d+)/)?.getAt(0)?.getAt(1) ?: ""
                echo "Build job submitted with ID: ${BUILD_JOB_ID}"
            }
        }
        stage('Create TMP Directory') {
            sh """
            ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'mkdir -p ${TMP_DIR}'
            """
        }
        stage('Submit Run Job') {
            withCredentials([[
                $class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials',
                accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
            ]]) {
                def binds = params.binds ?: ""
                def useGpu = params.useGpu ? "true" : "false"
                def exclusive = params.exclusive ? "true" : "false"
                def runOut = sh(
                    script: """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} '
                        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}";
                        export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}";
                        bash -s "${LOG_DIR}" "${SIF_PATH}" "${OVERLAY_PATH}" "${SSH_USER}" "${BUILD_JOB_ID}" "${params.runMem}" "${params.runCPUs}" "${params.runTime}" "${IMAGE}" "${TMP_DIR}" "${binds}" "${params.entrypointUrl}" "${useGpu}" "${exclusive}"
                    ' < library/run_job.sh
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
