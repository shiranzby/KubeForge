pipeline {
    agent {
        kubernetes {
            defaultContainer 'docker'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    ci-builder: "true"
  containers:
  - name: docker
    image: docker:29.7.2-cli
    command:
    - cat
    tty: true
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: "1"
        memory: 1Gi
    volumeMounts:
    - name: docker-socket
      mountPath: /var/run/docker.sock
    env:
    - name: HTTP_PROXY
      value: http://192.168.40.1:7890
    - name: HTTPS_PROXY
      value: http://192.168.40.1:7890
    - name: http_proxy
      value: http://192.168.40.1:7890
    - name: https_proxy
      value: http://192.168.40.1:7890
    - name: NO_PROXY
      value: 127.0.0.1,localhost,.svc,.cluster.local,10.96.0.0/12,10.233.0.0/16,192.168.40.0/24
    - name: no_proxy
      value: 127.0.0.1,localhost,.svc,.cluster.local,10.96.0.0/12,10.233.0.0/16,192.168.40.0/24
  volumes:
  - name: docker-socket
    hostPath:
      path: /var/run/docker.sock
      type: Socket
'''
        }
    }

    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        IMAGE_SOURCE = 'https://github.com/shiranzby/KubeForge'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHA = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
                    env.IMAGE_TAG = env.GIT_SHA.take(12)
                }
                sh '''
                    set -eu
                    : "${ACR_IMAGE:?Set ACR_IMAGE in Jenkins Global properties}"
                    echo "commit=$GIT_SHA"
                    echo "image=$ACR_IMAGE:$IMAGE_TAG"
                    docker version
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    set -eu
                    test -s Dockerfile
                    test -s index.html
                    grep -Fq 'KubeForge' index.html
                    if [ -x scripts/test.sh ]; then
                      ./scripts/test.sh
                    fi
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    set -eu
                    docker build \
                      --label "org.opencontainers.image.source=$IMAGE_SOURCE" \
                      --label "org.opencontainers.image.revision=$GIT_SHA" \
                      --label "org.opencontainers.image.version=$IMAGE_TAG" \
                      --tag "$ACR_IMAGE:$IMAGE_TAG" \
                      .
                    docker image inspect "$ACR_IMAGE:$IMAGE_TAG" \
                      --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
                '''
            }
        }

        stage('Verify Image') {
            steps {
                sh '''
                    set -eu
                    CANDIDATE="kubeforge-ci-$BUILD_NUMBER"
                    docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true
                    docker run -d --name "$CANDIDATE" "$ACR_IMAGE:$IMAGE_TAG"
                    docker exec "$CANDIDATE" nginx -t
                    docker exec "$CANDIDATE" sh -c 'wget -qO- http://127.0.0.1/ | grep -F KubeForge'
                    docker rm -f "$CANDIDATE" >/dev/null
                '''
            }
        }

        stage('Push') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'acr-kubeforge',
                        usernameVariable: 'ACR_USERNAME',
                        passwordVariable: 'ACR_PASSWORD'
                    )
                ]) {
                    sh '''
                        set -eu
                        set +x
                        ACR_REGISTRY="${ACR_IMAGE%%/*}"
                        printf '%s' "$ACR_PASSWORD" |
                          docker login "$ACR_REGISTRY" \
                            --username "$ACR_USERNAME" \
                            --password-stdin
                        docker push "$ACR_IMAGE:$IMAGE_TAG"
                        docker logout "$ACR_REGISTRY" >/dev/null 2>&1 || true
                    '''
                }
            }
        }
    }

    post {
        always {
            sh '''
                set +e
                CANDIDATE="kubeforge-ci-$BUILD_NUMBER"
                docker rm -f "$CANDIDATE" >/dev/null 2>&1
                exit 0
            '''
        }
        success {
            echo 'CI passed; a Git-SHA image was pushed to ACR.'
        }
        failure {
            echo 'CI failed; inspect the failed stage.'
        }
    }
}
