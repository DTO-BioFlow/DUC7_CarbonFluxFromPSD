# DUC 7: Global Particulate Organic Carbon (POC) flux from Particle Size Distribution (PSD) data

Code to predict and visualise POC flux from Particle Size Distribution (PSD)
data collected by the Underwater Vision Profiler (UVP) in an R Shiny app.

This work is part of the DTO-BioFlow project (GA No. 101112823), which received
funding from the European Union’s Horizon Programme call
HORIZON-MISS-2022-OCEAN-01. It is part of Demonstrator Use Case 7 (DUC 7),
related to ecosystem services. More information is available at
<https://dto-bioflow.eu/use-cases/duc7-ecosystem-services-including-carbon-sequestration>.

## Run in EDITO

1. **Log in to EDITO** with your account ([datalab.dive.edito.eu](https://datalab.dive.edito.eu/)). If you do not have an account, click **Sign in** then **Create an account** (any email address can be used).

2. Navigate to the **Service catalog** in the left-hand menu.

3. Search for **Carbonfluxfrompsd** and click **Launch** when the service appears.

   <img width="2536" height="1044" alt="screenshot_servicefound" src="https://github.com/user-attachments/assets/1d0e4aa4-9847-4610-8775-f755bcb9179d" />

4. Customize your resource requirements if needed, then click **Launch** again.

5. Wait a minute for the service to initialize, then click **Open the service 🚀**.

   <img width="2542" height="1034" alt="screenshot_servicereadytobelaunched" src="https://github.com/user-attachments/assets/c2e414e8-047a-40d4-aad0-971353e8aea1" />

6. The Shiny web application will open.

   <img width="917" height="908" alt="shinyapp" src="https://github.com/user-attachments/assets/efa2ac74-aeae-4935-ab1a-92426739a39d" />


### Application User Guide

The interface is divided into two main sections:

#### 1. Prediction Parameters (Left Panel)

* **Months selection:** Choose the months for which you want to run the model (leave default to run the entire year).
* **Target depth (m):** Set the depth at which you want to compute the gravitational POC flux. Depth must be between **100 m and 1,500 m** to ensure optimal model performance.
* **Bootstrap iterations:** Define the number of iterations (between **10 and 200**).
* **Spatial box:** Set the geographic boundaries using the two sliders.
* **Display type:** Select your preferred visualization mode:
  * **Annual mean:** Displays a yearly averaged map.
  * **Per month:** Displays monthly maps arranged in a 3x4 grid.

Once you are satisfied with your settings, click **Run the model**.

#### 2. Results & Performance (Right Panel)

The right panel features 4 tabs:

1. **Gravitational POC flux map:** Displays the flux map (in $\text{mgC}\cdot\text{m}^{-2}\cdot\text{day}^{-1}$) along with the total gravitational POC flux integrated over your selected period and spatial area.
2. **PSD coefficients:** Shows maps of the PSD coefficients. Use the drop-down menu to switch between the **intercept**, **slope**, and **quadratic** coefficients.
3. **Model performance:** Displays the model performance metrics and predictive variable importance derived from the pre-trained model.
4. **Data Download:** Provides a preview of the downloadable data, explains the variables, and allows you to download the results via the **Download results (CSV)** button.

Enjoy!


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
