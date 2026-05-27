# Update package list
sudo apt update && sudo apt upgrade -y

# Add Docker's official GPG key:
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
 "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
 $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
 sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update && sudo apt upgrade -y

# List the available versions:
apt-cache madison docker-ce | awk '{ print $3 }'

# 23.0.6 버전 설치
VERSION_STRING=5:23.0.6-1~ubuntu.22.04~jammy
sudo apt-get install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin

# 도커 그룹에 현재 사용자 추가 (sudo 없이 실행 가능하게)
sudo usermod -aG docker $USER

# 이미지 다운로드
docker pull hello-world

# 이미지 실행
sudo docker run hello-world

# 도커 버전 확인
sudo docker version
