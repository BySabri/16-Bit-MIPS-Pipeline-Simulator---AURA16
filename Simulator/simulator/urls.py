"""
URL configuration for simulator app.
"""

from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('assemble', views.assemble_code, name='assemble'),
    path('step', views.step_cpu, name='step'),
    path('step_back', views.step_back_cpu, name='step_back'),
    path('reset', views.reset_cpu, name='reset'),
    path('run', views.run_all, name='run'),
]
