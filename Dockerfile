# ============================================================
# Stage 1: Descarga y verificación de binarios
# ============================================================
FROM ubuntu:22.04@sha256:f9ff1df8e3e896d1c031de656e6b21ef91329419aba21e4a2029f0543e97243b AS downloader

ARG MAVEN_VERSION="3.9.12"
ARG TERRAFORM_VERSION="1.13.3"
ARG KUBECTL_VERSION="1.34.1"
ARG KUBELOGIN_VERSION="0.2.12"
ARG VEX_VERSION="1.0.20"
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN mkdir -p /opt/bin

RUN curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tar.gz && \
    mkdir -p /opt/maven && \
    tar -xzf /tmp/maven.tar.gz -C /opt/maven --strip-components=1

RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" -o /tmp/terraform.zip && \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o /tmp/terraform.sha256 && \
    grep "linux_${TARGETARCH}.zip" /tmp/terraform.sha256 | sed "s|terraform_.*_linux_${TARGETARCH}.zip|/tmp/terraform.zip|" | sha256sum --check && \
    unzip /tmp/terraform.zip -d /opt/bin/

RUN curl -fsSL "https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}/kubelogin-linux-${TARGETARCH}.zip" -o /tmp/kubelogin.zip && \
    curl -fsSL "https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}/kubelogin-linux-${TARGETARCH}.zip.sha256" -o /tmp/kubelogin.sha256 && \
    sed "s|kubelogin-linux-${TARGETARCH}.zip|/tmp/kubelogin.zip|" /tmp/kubelogin.sha256 | sha256sum --check && \
    unzip /tmp/kubelogin.zip -d /tmp && \
    mv /tmp/bin/linux_${TARGETARCH}/kubelogin /opt/bin/

RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /opt/bin/kubectl && \
    curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" -o /tmp/kubectl.sha256 && \
    echo "$(cat /tmp/kubectl.sha256)  /opt/bin/kubectl" | sha256sum --check && \
    chmod +x /opt/bin/kubectl

RUN curl -fsSL "https://github.com/jairoprogramador/vex-engine/releases/download/v${VEX_VERSION}/vexd_linux_${TARGETARCH}.tar.gz" -o /tmp/vexd.tar.gz && \
    curl -fsSL "https://github.com/jairoprogramador/vex-engine/releases/download/v${VEX_VERSION}/vexd_${VEX_VERSION}_checksums.txt" -o /tmp/vexd.sha256 && \
    grep "vexd_linux_${TARGETARCH}.tar.gz" /tmp/vexd.sha256 | sed "s|vexd_linux_${TARGETARCH}.tar.gz|/tmp/vexd.tar.gz|" | sha256sum --check && \
    mkdir -p /tmp/vexd && \
    tar -xzf /tmp/vexd.tar.gz -C /tmp/vexd && \
    mv /tmp/vexd/vexd /opt/bin/ && \
    chmod 755 /opt/bin/vexd

RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /opt/microsoft.asc

# ============================================================
# Stage 2: Imagen final de runtime
# ============================================================
FROM ubuntu:22.04@sha256:f9ff1df8e3e896d1c031de656e6b21ef91329419aba21e4a2029f0543e97243b

ARG DEV_GID=1001
ARG DEV_UID=1001
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN groupadd -o --system --gid "$DEV_GID" vex && \
    useradd --system --uid "$DEV_UID" --gid vex --shell /bin/bash --create-home vex

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=downloader /opt/microsoft.asc /etc/apt/keyrings/microsoft.asc
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.asc] https://packages.microsoft.com/repos/azure-cli/ jammy main" \
    > /etc/apt/sources.list.d/azure-cli.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends git openjdk-17-jdk-headless azure-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=downloader /opt/maven /usr/share/maven
COPY --from=downloader /opt/bin/terraform   /usr/local/bin/
COPY --from=downloader /opt/bin/kubectl     /usr/local/bin/
COPY --from=downloader /opt/bin/kubelogin   /usr/local/bin/
COPY --from=downloader /opt/bin/vexd        /usr/local/bin/

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-${TARGETARCH}
ENV MAVEN_HOME=/usr/share/maven
ENV PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"
    
USER vex

RUN git config --global --add safe.directory '*'

WORKDIR /home/vex/app

ENTRYPOINT [ "vexd", "run" ]