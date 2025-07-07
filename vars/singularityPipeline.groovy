def call(Map params) {

    pipeline {
        agent any

        environment {
            SSH_USER    = "${params.sshUser}"
            IMAGE       = "${params.image}"
            SCRATCH_DIR = "${params.scratchDir}"
            LOG_DIR     = "${params.logDir}"
            SIF_PATH    = "${params.scratchDir}/images/${params.image}.sif"
            OVERLAY_PATH= "${params.scratchDir}/${params.image}.ext3"
            TMP_DIR     = "${params.scratchDir}/tmp"
            DOCKER_URL  = "${params.dockerUrl}"
            SCRIPT_BASE_URL = 'https://raw.githubusercontent.com/thewillyP/jenkins/main/library'
        }

        stages {

            stage('Detect Hostname') {
                steps {
                    script {
                        env.EXEC_HOST = sh(script: "hostname", returnStdout: true).trim()
                        echo "Executor host: ${env.EXEC_HOST}"
                    }
                }
            }

            stage('Cancel Existing Jobs') {
                steps {
                    sh """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'curl -fsSL ${SCRIPT_BASE_URL}/cancel_jobs.sh | bash -s ${SSH_USER} ${IMAGE}'
                    """
                }
            }

            stage('Build Image If Needed') {
                steps {
                    script {
                        def imageExists = sh(
                            script: "ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} '[ -f ${SIF_PATH} ] && echo exists || echo missing'",
                            returnStdout: true
                        ).trim()

                        if (params.forceRebuild || imageExists == "missing") {
                            echo "Submitting image build job..."
                            def buildOut = sh(
                                script: """
                                ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                                'curl -fsSL ${SCRIPT_BASE_URL}/build_image.sh | bash -s \\
                                "${SCRATCH_DIR}" "${OVERLAY_PATH}" "${SIF_PATH}" "${DOCKER_URL}" "${LOG_DIR}" "${IMAGE}" \\
                                "${params.buildMem}" "${params.buildCPUs}" "${params.overlaySrc}" "${params.buildTime}"'
                                """,
                                returnStdout: true
                            ).trim()

                            env.BUILD_JOB_ID = (buildOut =~ /Submitted batch job (\\d+)/)[0][1]
                            echo "Build Job ID: ${env.BUILD_JOB_ID}"
                        } else {
                            echo "Image already exists. Skipping build."
                            env.BUILD_JOB_ID = ""
                        }
                    }
                }
            }

            stage('Create TMP Directory') {
                steps {
                    sh """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} 'mkdir -p ${TMP_DIR}'
                    """
                }
            }

            stage('Submit Run Job') {
                steps {
                    sh """
                    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                    'curl -fsSL ${SCRIPT_BASE_URL}/run_job.sh | bash -s \\
                    "${LOG_DIR}" "${SIF_PATH}" "${OVERLAY_PATH}" "${SSH_USER}" "" "${BUILD_JOB_ID}" \\
                    "${params.runMem}" "${params.runCPUs}" "${params.runTime}" "${IMAGE}" "${TMP_DIR}" "" "${params.entrypointUrl}"'
                    """
                }
            }
        }
    }
}