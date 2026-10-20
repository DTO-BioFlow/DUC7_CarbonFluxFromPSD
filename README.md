# DUC 7: Global Particulate Organic Carbon (POC) flux from Particle Size Distribution (PSD) data

Code to predict and visualise POC flux from Particle Size Distribution (PSD)
data collected by the Underwater Vision Profiler (UVP) in an R Shiny app.

This work is part of the DTO-BioFlow project (GA No. 101112823), which received
funding from the European Union’s Horizon Programme call
HORIZON-MISS-2022-OCEAN-01. It is part of Demonstrator Use Case 7 (DUC 7),
related to ecosystem services. More information is available at
<https://dto-bioflow.eu/use-cases/duc7-ecosystem-services-including-carbon-sequestration>.

## Run locally

The app uses port `3838`.

```powershell
Rscript app.R
```

Open <http://localhost:3838>.

## Build, run, and publish with Docker

Use one image name for the local and Docker Hub image:

```text
{docker_user_name}/{docker_image_name}:{version}
```

Replace the placeholders in the commands below. For example:

```text
docker_user_name = willemboone
docker_image_name = duc7-carbonflux
version = v1.0
```

Log in to Docker Hub:

```powershell
docker login
```

Build the image:

```powershell
docker build -t {docker_user_name}/{docker_image_name}:{version} .
```

Run the image locally:

```powershell
docker run --rm -p 3838:3838 {docker_user_name}/{docker_image_name}:{version}
```

Open <http://localhost:3838>.

Push the same image to Docker Hub:

```powershell
docker push {docker_user_name}/{docker_image_name}:{version}
```

The Docker Hub repository
`{docker_user_name}/{docker_image_name}` must exist before pushing. The
container listens on port `3838`, and the `-p 3838:3838` option maps it to the
same port on the host.
