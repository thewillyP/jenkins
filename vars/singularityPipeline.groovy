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
            def EXEC_HOST = sh(script: "hostname", returnStdout: true).trim()
            echo "Executor host: ${EXEC_HOST}"

            stage('Cancel Existing Jobs') {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    def cancelScript = """
                        #!/bin/bash
                        set -e
                        mkdir -p /tmp/scripts
                        curl -fsSL ${SCRIPT_BASE_URL}/cancel_jobs.sh -o /tmp/scripts/cancel_jobs.sh
                        curl -fsSL ${SCRIPT_BASE_URL}/cancel_jobs.sh.sig -o /tmp/scripts/cancel_jobs.sh.sig
                        singularity run \\
                            --cleanenv \\
                            --env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY,AWS_DEFAULT_REGION=us-east-1 \\
                            docker://amazon/aws-cli \\
                            ssm get-parameter --name "/gpg/public-key" --with-decryption --query Parameter.Value --output text > /tmp/scripts/public.key
                        gpg --import /tmp/scripts/public.key
                        gpg --verify /tmp/scripts/cancel_jobs.sh.sig /tmp/scripts/cancel_jobs.sh
                        if [ \$? -eq 0 ]; then
                            bash /tmp/scripts/cancel_jobs.sh ${SSH_USER} ${IMAGE}
                        else
                            echo "GPG verification failed"
                            exit 1
                        fi
                        rm -rf /tmp/scripts
                    """
                    def encodedScript = cancelScript.bytes.encodeBase64().toString()
                    sh """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                    AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \\
                    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \\
                    bash -c "echo '${encodedScript}' | base64 -d | bash"
                    """
                }
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
                def exclusive = params.exclusive ? "true" : "false"

                def runOut = sh(
                    script: """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                    'curl -fsSL ${SCRIPT_BASE_URL}/run_job.sh | bash -s \\
                    "${LOG_DIR}" "${SIF_PATH}" "${OVERLAY_PATH}" "${SSH_USER}" "${BUILD_JOB_ID}" \\
                    "${params.runMem}" "${params.runCPUs}" "${params.runTime}" "${IMAGE}" "${TMP_DIR}" \\
                    "${binds}" "${params.entrypointUrl}" "${useGpu}" "${exclusive}"'
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