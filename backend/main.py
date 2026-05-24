from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import asyncio
import json

app = FastAPI(title="Obstacle Detection Mock Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

OBSTACLE_MESSAGES = [
    "A car is ahead of you, slow down",
    "Pedestrian crossing on your right, stop",
    "Bicycle approaching from the left",
    "Wall ahead, turn right now",
    "Speed bump in two metres",
    "Dog crossing the path, wait",
    "Narrow passage ahead, proceed slowly",
]


@app.get("/obstacle-stream")
async def obstacle_stream():
    """
    SSE endpoint. Sends one obstacle instruction every 5 seconds,
    cycling through the mock messages indefinitely.
    """
    async def generate():
        index = 0
        while True:
            message = OBSTACLE_MESSAGES[index % len(OBSTACLE_MESSAGES)]
            payload = json.dumps({"res": message})
            yield f"data: {payload}\n\n"
            index += 1
            await asyncio.sleep(10)

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.get("/health")
async def health():
    return {"status": "ok"}