FROM gitpod/workspace-flutter

# Install custom tools, runtimes, etc.
# For example "bastet", a command-line tetris clone:
# RUN brew install bastet
#
# More information: https://www.gitpod.io/docs/config-docker/
ENV ANDROID_HOME=/home/gitpod/development/android-sdk
ENV JAVA_HOME=/home/gitpod/.sdkman/candidates/java/current
RUN bash -c ". /home/gitpod/.sdkman/bin/sdkman-init.sh \
             && sdk install java 8.0.265.j9-adpt"

RUN mkdir -p /home/gitpod/.android && \
    touch /home/gitpod/.android/repositories.cfg

RUN echo "Installing Android SDK..." && \
    mkdir -p /home/gitpod/development/android-sdk && cd /home/gitpod/development/android-sdk && wget https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip && unzip sdk-tools-linux-4333796.zip && rm -f sdk-tools-linux-4333796.zip && \
    chmod +x /home/gitpod/development/android-sdk/tools/bin/sdkmanager && \
    yes | /home/gitpod/development/android-sdk/tools/bin/sdkmanager "platform-tools" "platforms;android-28" "build-tools;28.0.3"
