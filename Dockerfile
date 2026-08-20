ARG BASE_IMAGE=rocker/r-ver:4.5.1
FROM ${BASE_IMAGE}
USER root

ARG UBUNTU_MIRROR=https://mirrors.aliyun.com/ubuntu
ARG CRAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/CRAN/
ARG BIOCONDUCTOR_MIRROR=https://bioconductor.posit.co
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ARG RUST_VERSION=1.85.1
ARG RUSTUP_INIT_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
ARG RUSTUP_DIST_SERVER=https://rsproxy.cn
ARG RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup

RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i -E "s|https?://archive.ubuntu.com/ubuntu/?|${UBUNTU_MIRROR}|g; s|https?://security.ubuntu.com/ubuntu/?|${UBUNTU_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i -E "s|https?://archive.ubuntu.com/ubuntu/?|${UBUNTU_MIRROR}|g; s|https?://security.ubuntu.com/ubuntu/?|${UBUNTU_MIRROR}|g" /etc/apt/sources.list; \
    fi; \
    printf '%s\n' \
      'Acquire::Retries "5";' \
      'Acquire::ForceIPv4 "true";' \
      'Acquire::http::Timeout "45";' \
      'Acquire::https::Timeout "45";' \
      > /etc/apt/apt.conf.d/80-bioagent-network; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv build-essential cmake curl \
    libcurl4-openssl-dev libcairo2-dev \
    libssl-dev libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff-dev libjpeg-dev libgit2-dev fonts-noto-cjk \
    libglpk-dev libgsl-dev libnlopt-dev libuv1-dev; \
    rm -rf /var/lib/apt/lists/*

ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER} \
    RUSTUP_UPDATE_ROOT=${RUSTUP_UPDATE_ROOT} \
    PATH=/usr/local/cargo/bin:${PATH}
RUN set -eux; \
    installed_rust="$(rustc --version 2>/dev/null | awk '{print $2}' || true)"; \
    if [ "${installed_rust}" != "${RUST_VERSION}" ]; then \
      case "$(uname -m)" in \
        x86_64) rust_target=x86_64-unknown-linux-gnu ;; \
        aarch64|arm64) rust_target=aarch64-unknown-linux-gnu ;; \
        *) echo "Unsupported Rust architecture: $(uname -m)" >&2; exit 1 ;; \
      esac; \
      curl --fail --location --retry 5 \
        "${RUSTUP_INIT_ROOT}/dist/${rust_target}/rustup-init" \
        --output /tmp/rustup-init; \
      chmod +x /tmp/rustup-init; \
      /tmp/rustup-init -y --profile minimal \
        --default-toolchain "${RUST_VERSION}" --no-modify-path; \
      rm -f /tmp/rustup-init; \
    fi; \
    rustc --version; \
    cargo --version

COPY r/install_dependencies.R /tmp/install_dependencies.R
ENV CRAN_MIRROR=${CRAN_MIRROR}
ENV BIOCONDUCTOR_MIRROR=${BIOCONDUCTOR_MIRROR}
# Keep the expensive dependency families in separate Docker layers. A
# transient failure in Bioconductor or GitHub can then resume from the last
# successful layer instead of recompiling every CRAN package.
RUN AMPLICON_R_INSTALL_PHASE=cran Rscript /tmp/install_dependencies.R
RUN AMPLICON_R_INSTALL_PHASE=bioc Rscript /tmp/install_dependencies.R
RUN AMPLICON_R_INSTALL_PHASE=final Rscript /tmp/install_dependencies.R

WORKDIR /app
COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY r ./r
COPY scripts/manage_access.py ./scripts/manage_access.py
RUN Rscript r/check_dependencies.R /tmp/dependency_status.csv
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    --retries 5 --timeout 60 --index-url "${PIP_INDEX_URL}" ".[web]"

ENV AMPLICON_WORKSPACE=/workspace \
    AMPLICON_R_ROOT=/app/r \
    AMPLICON_PLOT_FONT="Noto Sans CJK SC"
RUN (id -u bioagent >/dev/null 2>&1 || useradd --create-home --uid 10001 bioagent) \
    && mkdir -p /workspace \
    && chown -R bioagent:bioagent /workspace /app
USER bioagent
ENTRYPOINT []
CMD ["amplicon-agent"]
