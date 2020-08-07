FROM gitpod/workspace-flutter

# Install custom tools, runtimes, etc.
# For example "bastet", a command-line tetris clone:
# RUN brew install bastet
#
# More information: https://www.gitpod.io/docs/config-docker/
ENV ANDROID_HOME=/workspace/android-sdk

RUN bash -c ". /home/gitpod/.sdkman/bin/sdkman-init.sh \
             && sdk install java 8.0.242.j9-adpt"

RUN echo "Installing Android SDK..." && \
    mkdir -p /workspace/android-sdk && cd /workspace/android-sdk && wget https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip && unzip sdk-tools-linux-4333796.zip && rm -f sdk-tools-linux-4333796.zip && \
    /workspace/android-sdk/tools/bin/sdkmanager "platform-tools" "platforms;android-28" "build-tools;28.0.3"
