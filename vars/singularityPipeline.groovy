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
        def REMOTE_SCRIPT_DIR = "/tmp/${sh(script: 'head /dev/urandom | tr -dc a-z0-9 | head -c 8', returnStdout: true).trim()}"
        def EXEC_HOST = sh(script: "hostname", returnStdout: true).trim()
        echo "Executor host: ${EXEC_HOST}"

        stage('Checkout Scripts') {
            checkout([
                $class: 'GitSCM',
                branches: [[name: '*/main']],
                userRemoteConfigs: [[url: 'https://github.com/thewillyP/jenkins.git']]
            ])
            sh """
            ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'mkdir -p ${REMOTE_SCRIPT_DIR}'
            scp -o StrictHostKeyChecking=no -r library ${SSH_USER}@${EXEC_HOST}:${REMOTE_SCRIPT_DIR}/
            """
        }

        stage('Cancel Existing Jobs') {
            sh """
            ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
            'bash ${REMOTE_SCRIPT_DIR}/library/cancel_jobs.sh ${SSH_USER} ${IMAGE}'
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
                    'bash ${REMOTE_SCRIPT_DIR}/library/build_image.sh \\
                    "${SCRATCH_DIR}" "${OVERLAY_PATH}" "${SIF_PATH}" "${DOCKER_URL}" "${LOG_DIR}" "${IMAGE}" \\
                    "${params.buildMem}" "${params.buildCPUs}" "${params.overlaySrc}" "${params.buildTime}"'
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
                            export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}";
                            bash -s
                        ' < library/run_job.sh '${LOG_DIR}' '${SIF_PATH}' '${OVERLAY_PATH}' '${SSH_USER}' '${BUILD_JOB_ID}' '${params.runMem}' '${params.runCPUs}' '${params.runTime}' '${IMAGE}' '${TMP_DIR}' '${binds}' '${params.entrypointUrl}' '${useGpu}' '${exclusive}'
                    """,
                    returnStdout: true
                ).trim()

                runJobId = (runOut =~ /Submitted batch job (\d+)/)?.getAt(0)?.getAt(1) ?: ""
                echo "Run job submitted with ID: ${runJobId}"
            }
        }

        stage('Cleanup Remote Scripts') {
            sh """
            ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'rm -rf ${REMOTE_SCRIPT_DIR}'
            """
        }
    }

    return runJobId
}