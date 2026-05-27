sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    python3-dev \
    python3-pip \
    libportaudio2 \
    libportaudiocpp0 \
    portaudio19-dev \
    ffmpeg \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libx11-dev \
    libatlas-base-dev \
    libsndfile1 \
    libasound2-dev

# pip install mediapipe
pip install python-dotenv
pip install opencv-python
pip install scipy
pip install ultralytics
pip install supervision
pip install httpx
pip install scikit-learn
pip install pyaudio
pip install openwakeword
pip install langchain-upstage
pip install pymodbus==2.5.3
