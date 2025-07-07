def call(Map params) {

    pipeline {
        agent any

        environment {
            SSH_USER = params.SSH_USER
            IMAGE = params.IMAGE
            SCRATCH_DIR = params.SCRATCH_DIR
            LOG_DIR = params.LOG_DIR
            SIF_PATH = "${params.SCRATCH_DIR}/images/${params.IMAGE}.sif"
            OVERLAY_PATH = "${params.SCRATCH_DIR}/${params.IMAGE}.ext3"
            TMP_DIR = "${params.SCRATCH_DIR}/tmp"
            DOCKER_URL = params.DOCKER_URL
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
                    ssh -o StrictHostKeyChecking=no ${sshUser}@${EXEC_HOST} 'curl -fsSL ${SCRIPT_BASE_URL}/cancel_jobs.sh | bash -s ${sshUser} ${imageBaseName}'
                    """
                }
            }

            stage('Build Image If Needed') {
                steps {
                    script {
                        def imageExists = sh(
                            script: "ssh -o StrictHostKeyChecking=no ${sshUser}@${EXEC_HOST} '[ -f ${SIF_PATH} ] && echo exists || echo missing'",
                            returnStdout: true
                        ).trim()

                        if (forceRebuild || imageExists == "missing") {
                            echo "Submitting image build job..."
                            def buildOut = sh(
                                script: """
                                ssh -o StrictHostKeyChecking=no ${sshUser}@${EXEC_HOST} \\
                                'curl -fsSL ${SCRIPT_BASE_URL}/build_image.sh | bash -s \\
                                "${scratchDir}" "${OVERLAY_PATH}" "${SIF_PATH}" "${dockerUrl}" "${logDir}" "${imageBaseName}" \\
                                "${buildMem}" "${buildCPUs}" "${overlaySrc}" "${buildTime}"'
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
                    ssh -o StrictHostKeyChecking=no ${sshUser}@${EXEC_HOST} 'mkdir -p ${TMP_DIR}'
                    """
                }
            }

            stage('Submit Run Job') {
                steps {
                    sh """
                    ssh -o StrictHostKeyChecking=no ${sshUser}@${EXEC_HOST} \\
                    'curl -fsSL ${SCRIPT_BASE_URL}/run_job.sh | bash -s \\
                    "${logDir}" "${SIF_PATH}" "${OVERLAY_PATH}" "${sshUser}" "" "${BUILD_JOB_ID}" \\
                    "${runMem}" "${runCPUs}" "${runTime}" "${imageBaseName}" "${TMP_DIR}" "" "${entrypointUrl}"'
                    """
                }
            }
        }
    }
}
