from fastapi import APIRouter

from app.api.routes.catalogue import router as catalogue_router
from app.api.routes.health import router as health_router
from app.api.routes.shop import router as shop_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(catalogue_router)
api_router.include_router(shop_router)
