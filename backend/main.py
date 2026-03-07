"""
Backend server for spaceship image generation using Replicate Flux API.
Background removal via fal.ai BEN API.

Environment Variables:
    REPLICATE_API_TOKEN: Replicate API token (required)
    FAL_KEY: fal.ai API key (required for background removal)
    PORT: Server port (default: 8742)
"""

import os
import io
import base64
from dotenv import load_dotenv
load_dotenv()

import asyncio
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import replicate

app = FastAPI(title="Spaceship Image Generator API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

REPLICATE_API_TOKEN = os.getenv("REPLICATE_API_TOKEN", "")
FAL_KEY = os.getenv("FAL_KEY", "")
FLUX_MODEL = "black-forest-labs/flux-2-klein-9b"
FAL_BEN_URL = "https://fal.run/fal-ai/ben/v2/image"

# Store pending predictions for polling
_predictions: dict = {}


class ImageRequest(BaseModel):
    prompt: str
    reference_images: list[str] = []  # Up to 5 public URLs
    aspect_ratio: str = "16:9"
    remove_background: bool = True  # Remove background by default


class ImageResponse(BaseModel):
    status: str
    job_id: Optional[str] = None
    image_url: Optional[str] = None
    image_data: Optional[str] = None  # Base64 PNG with transparency
    error: Optional[str] = None
    progress: Optional[int] = 0


async def remove_background_fal(image_url: str) -> bytes:
    """Remove background from image using fal.ai BEN API."""
    print(f"[remove_background] Processing via fal.ai: {image_url[:60]}...")
    
    async with httpx.AsyncClient(timeout=120.0) as client:
        # Call fal.ai BEN API
        resp = await client.post(
            FAL_BEN_URL,
            headers={
                "Authorization": f"Key {FAL_KEY}",
                "Content-Type": "application/json"
            },
            json={"image_url": image_url}
        )
        
        if resp.status_code != 200:
            raise Exception(f"fal.ai error: {resp.status_code} - {resp.text}")
        
        result = resp.json()
        output_url = result.get("image", {}).get("url", "")
        
        if not output_url:
            raise Exception("No output URL from fal.ai")
        
        print(f"[remove_background] Got result: {output_url[:60]}...")
        
        # Download the processed image
        img_resp = await client.get(output_url)
        img_resp.raise_for_status()
        
        print("[remove_background] Done")
        return img_resp.content


@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "replicate_configured": bool(REPLICATE_API_TOKEN),
        "fal_configured": bool(FAL_KEY),
        "model": FLUX_MODEL,
        "background_removal": "fal.ai/ben"
    }


@app.post("/generate-image", response_model=ImageResponse)
async def generate_image(request: ImageRequest):
    """Submit image generation request to Replicate Flux."""
    if not REPLICATE_API_TOKEN:
        return ImageResponse(status="error", error="REPLICATE_API_TOKEN not configured")
    
    if request.remove_background and not FAL_KEY:
        return ImageResponse(status="error", error="FAL_KEY not configured (needed for background removal)")
    
    prompt = request.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
    
    # Validate reference images (max 5)
    reference_images = request.reference_images[:5]
    
    print(f"[generate-image] Prompt: {prompt[:80]}...")
    print(f"[generate-image] Reference images: {len(reference_images)}")
    print(f"[generate-image] Aspect ratio: {request.aspect_ratio}")
    print(f"[generate-image] Remove background: {request.remove_background}")
    
    try:
        # Build input for Flux model
        model_input = {
            "prompt": prompt,
            "aspect_ratio": request.aspect_ratio,
            "go_fast": True,
            "output_format": "png",
            "output_quality": 95,
        }
        
        # Add reference images if provided
        if reference_images:
            model_input["images"] = reference_images
        
        # Create prediction (async)
        prediction = replicate.predictions.create(
            model=FLUX_MODEL,
            input=model_input
        )
        
        job_id = prediction.id
        _predictions[job_id] = {
            "prediction": prediction,
            "prompt": prompt[:50],
            "remove_background": request.remove_background
        }
        
        print(f"[generate-image] Created prediction: {job_id}")
        return ImageResponse(status="processing", job_id=job_id, progress=10)
        
    except replicate.exceptions.ReplicateError as e:
        print(f"[generate-image] Replicate error: {e}")
        return ImageResponse(status="error", error=f"Replicate API error: {str(e)}")
    except Exception as e:
        print(f"[generate-image] Error: {e}")
        return ImageResponse(status="error", error=str(e))


@app.get("/job-status/{job_id}", response_model=ImageResponse)
async def get_job_status(job_id: str):
    """Poll for image generation completion."""
    if not REPLICATE_API_TOKEN:
        return ImageResponse(status="error", error="REPLICATE_API_TOKEN not configured")
    
    try:
        # Get stored prediction info
        pred_info = _predictions.get(job_id, {})
        should_remove_bg = pred_info.get("remove_background", True)
        
        # Reload prediction status
        prediction = replicate.predictions.get(job_id)
        
        status = prediction.status
        print(f"[job-status] {job_id}: {status}")
        
        if status == "succeeded":
            # Get output URL(s)
            output = prediction.output
            if isinstance(output, list) and len(output) > 0:
                first = output[0]
                image_url = first.url if hasattr(first, "url") else str(first)
            else:
                image_url = output.url if hasattr(output, "url") else str(output)
            
            # If background removal requested, process via fal.ai
            if should_remove_bg and FAL_KEY:
                print(f"[job-status] Removing background via fal.ai...")
                try:
                    processed_bytes = await remove_background_fal(image_url)
                    image_data = base64.b64encode(processed_bytes).decode("utf-8")
                    
                    _predictions.pop(job_id, None)
                    return ImageResponse(
                        status="completed",
                        image_data=image_data,
                        progress=100
                    )
                except Exception as e:
                    print(f"[job-status] Background removal failed: {e}")
                    # Fall back to returning URL without background removal
                    _predictions.pop(job_id, None)
                    return ImageResponse(status="completed", image_url=image_url, progress=100)
            else:
                _predictions.pop(job_id, None)
                return ImageResponse(status="completed", image_url=image_url, progress=100)
        
        elif status == "failed":
            error_msg = getattr(prediction, "error", "Generation failed")
            _predictions.pop(job_id, None)
            return ImageResponse(status="failed", error=str(error_msg))
        
        elif status == "canceled":
            _predictions.pop(job_id, None)
            return ImageResponse(status="failed", error="Generation was canceled")
        
        else:
            # Still processing (starting, processing)
            progress = 30 if status == "processing" else 10
            return ImageResponse(status="processing", job_id=job_id, progress=progress)
                
    except replicate.exceptions.ReplicateError as e:
        print(f"[job-status] Replicate error: {e}")
        return ImageResponse(status="error", error=f"Failed to get status: {str(e)}")
    except Exception as e:
        print(f"[job-status] Error: {e}")
        return ImageResponse(status="error", error=str(e))


@app.post("/generate-image-sync", response_model=ImageResponse)
async def generate_image_sync(request: ImageRequest):
    """
    Synchronous image generation - waits for completion.
    Useful for simple testing, but may timeout for slow generations.
    """
    if not REPLICATE_API_TOKEN:
        return ImageResponse(status="error", error="REPLICATE_API_TOKEN not configured")
    
    if request.remove_background and not FAL_KEY:
        return ImageResponse(status="error", error="FAL_KEY not configured")
    
    prompt = request.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
    
    reference_images = request.reference_images[:5]
    
    print(f"[generate-image-sync] Prompt: {prompt[:80]}...")
    print(f"[generate-image-sync] Reference images: {len(reference_images)}")
    print(f"[generate-image-sync] Remove background: {request.remove_background}")
    
    try:
        model_input = {
            "prompt": prompt,
            "aspect_ratio": request.aspect_ratio,
            "go_fast": True,
            "output_format": "png",
            "output_quality": 95,
        }
        
        if reference_images:
            model_input["images"] = reference_images
        
        # Run synchronously (blocks until complete)
        loop = asyncio.get_event_loop()
        output = await loop.run_in_executor(
            None,
            lambda: replicate.run(FLUX_MODEL, input=model_input)
        )
        
        # Extract URL from output
        if isinstance(output, list) and len(output) > 0:
            first = output[0]
            image_url = first.url if hasattr(first, "url") else str(first)
        else:
            image_url = output.url if hasattr(output, "url") else str(output)
        
        print(f"[generate-image-sync] Generated: {image_url}")
        
        # Remove background if requested
        if request.remove_background and FAL_KEY:
            print(f"[generate-image-sync] Removing background...")
            processed_bytes = await remove_background_fal(image_url)
            image_data = base64.b64encode(processed_bytes).decode("utf-8")
            return ImageResponse(status="completed", image_data=image_data, progress=100)
        else:
            return ImageResponse(status="completed", image_url=image_url, progress=100)
        
    except Exception as e:
        print(f"[generate-image-sync] Error: {e}")
        return ImageResponse(status="error", error=str(e))


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8742"))
    print(f"Spaceship Image Generator | Port: {port}")
    print(f"REPLICATE_API_TOKEN: {'[SET]' if REPLICATE_API_TOKEN else '[NOT SET]'}")
    print(f"FAL_KEY: {'[SET]' if FAL_KEY else '[NOT SET]'}")
    print(f"Model: {FLUX_MODEL}")
    print(f"Background removal: fal.ai/ben")
    uvicorn.run(app, host="0.0.0.0", port=port)
