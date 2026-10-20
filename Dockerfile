# Use current Shiny image (Ubuntu 24.04 base)
FROM rocker/shiny:4.5

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies commonly needed by R spatial/data packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gfortran \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    libv8-dev \
    libpng-dev \
    libjpeg-dev \
    zlib1g-dev \
    libproj-dev \
    libgdal-dev \
    libgeos-dev \
    libudunits2-dev \
    libsqlite3-dev \
    libnetcdf-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /srv/shiny-server

# Install renv in a separate layer for better Docker cache reuse
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"

# Copy lockfile first so package restore is only rerun when dependencies change
COPY renv.lock /srv/shiny-server/renv.lock

# Restore packages from renv.lock
RUN R -e "renv::restore(lockfile='/srv/shiny-server/renv.lock', prompt=FALSE, clean=TRUE)"

# Copy app source after dependencies are restored
COPY . /srv/shiny-server

# Expose Shiny port
EXPOSE 3838

# Run the app
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server', host='0.0.0.0', port=3838)"]

