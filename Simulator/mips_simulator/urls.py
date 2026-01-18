"""
URL configuration for mips_simulator project.
"""
from django.urls import path, include

urlpatterns = [
    path('', include('simulator.urls')),
]
