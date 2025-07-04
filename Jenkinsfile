pipeline {
    agent any

    environment {
        SSH_USER = 'wlp9800'
        SCRIPT_URL = 'https://raw.githubusercontent.com/thewillyP/jenkins/main/devbox.sh'
    }

    stages {
        stage('Get Hostname') {
            steps {
                script {
                    env.EXEC_HOST = sh(script: 'hostname', returnStdout: true).trim()
                }
            }
        }

        stage('Launch Devbox') {
            steps {
                sh """
                ssh -o StrictHostKeyChecking=no ${SSH_USER}@${EXEC_HOST} \\
                  'curl -s ${SCRIPT_URL} | sbatch'
                """
            }
        }
    }
}
