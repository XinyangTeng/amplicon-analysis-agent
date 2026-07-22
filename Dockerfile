FROM rocker/r-ver:4.5.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv build-essential libcurl4-openssl-dev \
    libssl-dev libxml2-dev libfontconfig1-dev && rm -rf /var/lib/apt/lists/*

RUN R -q -e "install.packages(c('jsonlite','ggplot2','vegan'), repos='https://cloud.r-project.org')"

WORKDIR /app
COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY r ./r
COPY skills ./skills
RUN python3 -m pip install --break-system-packages --no-cache-dir .

ENV AMPLICON_WORKSPACE=/workspace
ENTRYPOINT ["amplicon-agent"]

