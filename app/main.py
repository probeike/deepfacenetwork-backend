from fastapi import FastAPI
import uvicorn

# Create FastAPI application
app = FastAPI(
    title="AI Agent Hello World",
    description="A simple Hello World API for AI Agent deployment demo",
    version="1.0.0"
)

@app.get("/")
async def root():
    """
    Root endpoint that returns a Hello World message
    """
    return {"message": "Hello World"}

@app.get("/health")
async def health():
    """
    Health check endpoint
    """
    return {"status": "healthy"}

if __name__ == "__main__":
    # Run the application with uvicorn when script is executed directly
    uvicorn.run("main:app", host="0.0.0.0", port=80, reload=False)