FROM ubuntu:jammy AS base
ARG BUILDKIT_SBOM_SCAN_STAGE=true
ARG KASMVNC_VERSION=1.3.3
RUN apt update && apt install wget openbox tar curl ssl-cert dbus-x11 sudo ca-certificates git xterm --no-install-recommends -y && \
    wget https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_jammy_${KASMVNC_VERSION}_amd64.deb && \
    apt install -y ./kasmvncserver_jammy_${KASMVNC_VERSION}_amd64.deb && \
    rm ./kasmvncserver_jammy_${KASMVNC_VERSION}_amd64.deb && \
    make-ssl-cert generate-default-snakeoil && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY kasmvnc-freeze-fix.patch /tmp/kasmvnc-freeze-fix.patch
RUN curl -fsSL https://deb.nodesource.com/setup_18.x -o- | bash && \
    apt update && apt-get install -y nodejs && \
    node -v && \
    npm -v && \
    echo "network:\n    protocol: http\n    interface: 0.0.0.0\n    use_ipv4: true\n    udp:\n      public_ip: 127.0.0.1\n      port: auto\n      stun_server: null\n" > /etc/kasmvnc/kasmvnc.yaml && \
    GIT_SSL_NO_VERIFY=true git clone https://github.com/kasmtech/noVNC.git /usr/share/kasmvnc/noVNC && \ 
    (cd /usr/share/kasmvnc/noVNC && git checkout 5c46b2e13ab1dd7232b28f017fd7e49ca740f5a4) && \
    (cd /usr/share/kasmvnc/noVNC && git apply /tmp/kasmvnc-freeze-fix.patch && npm install && npm run build) && \
    mv /usr/share/kasmvnc/www /usr/share/kasmvnc/www.old && \
    ln -sf /usr/share/kasmvnc/noVNC/dist /usr/share/kasmvnc/www && \
    apt remove nodejs --purge --autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ARG CUSTOM_USERNAME=container_user
ARG PUID=1000
ARG PGID=1000
RUN groupadd ${CUSTOM_USERNAME}  -g ${PGID} && \
    useradd ${CUSTOM_USERNAME}  -u ${PUID} -g ${PGID} -m -s /bin/bash && \
    usermod -aG video,audio,ssl-cert,sudo ${CUSTOM_USERNAME} && \
    echo "#!/bin/bash" > /entrypoint.sh && \
    echo 'trap exit INT TERM' >> /entrypoint.sh && \
    echo "sudo hostname -F /etc/hostname" >> /entrypoint.sh && \
    echo 'echo 127.0.0.1 `hostname` | sudo tee -a /etc/hosts' >> /entrypoint.sh && \
    echo 'echo -e "${VNC_PW}\n${VNC_PW}\n" | kasmvncpasswd -u kasm_user -wo' >> /entrypoint.sh && \
    echo 'while [ true ]; do (echo DISPLAY=$DISPLAY; kasmvncserver -list | grep -P "$DISPLAY\s+" || (rm -rf /tmp/.X* && kasmvncserver $DISPLAY -websocketPort 6901 -FrameRate=60 -interface 0.0.0.0 -BlacklistThreshold=0 -FreeKeyMappings -PreferBandwidth -DynamicQualityMin=4 -DynamicQualityMax=7 -DLP_ClipDelay=0 -sslOnly 0 -DisableBasicAuth -UseIPv6 0) && echo Wait 5s for Xvnc to start && sleep 5); kasmvncserver -list | grep -B2 -P "$DISPLAY\s+" && break; done' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh && \
    echo "${CUSTOM_USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${CUSTOM_USERNAME}

RUN sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized><decor>no</decor></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    /etc/xdg/openbox/rc.xml && \
    echo "**** theme ****" && \
    curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ 
USER ${CUSTOM_USERNAME} 
RUN mkdir -p $HOME/.vnc && \
    echo "exec openbox-session" > $HOME/.vnc/xstartup && \
    touch "$HOME/.vnc/.de-was-selected" && \
    chmod +x $HOME/.vnc/xstartup

ENV VNC_PW=vncpassword
ENV DISPLAY=:1
ENTRYPOINT ["/entrypoint.sh"]


FROM base AS keepassxc
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
USER root
RUN apt update && apt install -y keepassxc --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN echo "sudo chown -R ${CUSTOM_USERNAME}:${CUSTOM_USERNAME} /home/${CUSTOM_USERNAME}/.config/keepassxc" >> /entrypoint.sh 
RUN echo "while [ true ]; do keepassxc ; sleep 1; done" >> /entrypoint.sh 
USER ${CUSTOM_USERNAME}
VOLUME /home/${CUSTOM_USERNAME}/.config/keepassxc

FROM base AS chrome
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
ENV FLAGS=""
USER root
RUN apt update && \
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt install -y ./google-chrome-stable_current_amd64.deb systemd --no-install-recommends && \
    rm google-chrome-stable_current_amd64.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN echo "sudo chown -R ${CUSTOM_USERNAME}:${CUSTOM_USERNAME} /home/${CUSTOM_USERNAME}/.cache" >> /entrypoint.sh 
RUN echo "sudo chown -R ${CUSTOM_USERNAME}:${CUSTOM_USERNAME} /home/${CUSTOM_USERNAME}/.config" >> /entrypoint.sh 
RUN echo "sudo chown -R ${CUSTOM_USERNAME}:${CUSTOM_USERNAME} /home/${CUSTOM_USERNAME}/.pki" >> /entrypoint.sh 
RUN echo 'while [ true ]; do (set -x;google-chrome-stable --disable-dev-shm-usage $FLAGS); sleep 3; done' >> /entrypoint.sh 
USER ${CUSTOM_USERNAME} 
VOLUME /home/${CUSTOM_USERNAME}/.config/google/
VOLUME /home/${CUSTOM_USERNAME}/.config/google-chrome/
VOLUME /home/${CUSTOM_USERNAME}/.cache/google-chrome/

FROM base AS lens
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true
USER root
ARG LENS_VERSION
WORKDIR /home/${CUSTOM_USERNAME}
RUN apt update && apt install -y gpg && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google.list && \
    apt update && apt install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV AWS_VERSION=2.11.6
RUN apt update && apt install unzip -y && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_VERSION}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install -b /usr/local/bin && \
    rm -f awscliv2.zip  && \
    aws --version && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt update && \
    [ ! -n "${LENS_VERSION}" ] && LENS_VERSION=$(curl https://forums.k8slens.dev/c/announcements/release-notes/56 | grep -Po "class='title.*\<" | grep -Po '20\d\d\.\d+\.\d+-latest' | python3 -c 'import sys;input = sys.stdin.read();array = input.splitlines();array.sort(reverse=True);print(array[0])') || LENS_VERSION=${LENS_VERSION} && \
    curl https://downloads.k8slens.dev/apt/debian/pool/stable/main/Lens-${LENS_VERSION}_amd64.deb -o k8slens-latest_amd64.deb && \
    apt-get install -y ./k8slens-latest_amd64.deb  libasound2 && \
    mv /opt/Lens/lens-desktop /opt/Lens/lens-desktop-bin && \
    echo '2>&1 NODE_TLS_REJECT_UNAUTHORIZED=0 /opt/Lens/lens-desktop-bin $@ > /tmp/lens-desktop.logs' > /opt/Lens/lens-desktop && \
    chmod +x /opt/Lens/lens-desktop && \
    rm ./k8slens-latest_amd64.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "sudo chown -R ${CUSTOM_USERNAME}:${CUSTOM_USERNAME} /home/${CUSTOM_USERNAME}/.config/Lens" >> /entrypoint.sh 
RUN echo "while [ true ]; do /opt/Lens/lens-desktop ; sleep 1; done" >> /entrypoint.sh 
USER ${CUSTOM_USERNAME}
VOLUME /home/${CUSTOM_USERNAME}/.config/Lens
