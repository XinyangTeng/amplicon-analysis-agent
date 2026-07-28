FROM rocker/r-ver:4.5.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv build-essential libcurl4-openssl-dev \
    libssl-dev libxml2-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff-dev libjpeg-dev libgit2-dev \
    libglpk-dev libgsl-dev libnlopt-dev && rm -rf /var/lib/apt/lists/*

COPY r/install_dependencies.R /tmp/install_dependencies.R
RUN Rscript /tmp/install_dependencies.R

WORKDIR /app
COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY r ./r
RUN Rscript r/check_dependencies.R /tmp/dependency_status.csv
RUN python3 -m pip install --break-system-packages --no-cache-dir .

ENV AMPLICON_WORKSPACE=/workspace
ENTRYPOINT ["amplicon-agent"]
