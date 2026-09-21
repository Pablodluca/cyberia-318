# -*- coding: utf-8 -*-
# Copyright 2026 Pablo Daniel De Luca - Ink318 Software
# aprendizaje.py - CyberIA Evolutionary Memory Module
# Analiza conversaciones y actualiza la base de conocimientos sobre el usuario

import json
import os

MEMORIA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../config/memoria_cyberia.json")
LOG_CONVERSACIONES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "conversaciones.log")

def cargar_memoria():
    try:
        with open(MEMORIA_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {"usuario": {"nombre": "Pablo", "preferencias": {}, "hechos_recordados": []}, "relacion": {"nivel_confianza": 1}}

def guardar_memoria(memoria):
    with open(MEMORIA_PATH, "w", encoding="utf-8") as f:
        json.dump(memoria, f, indent=4, ensure_ascii=False)

def analizar_y_aprender(texto_conversacion):
    """
    En un entorno real, esto llamaría a Ollama para extraer hechos.
    Para la implementación base, simulamos la extracción de patrones clave.
    """
    memoria = cargar_memoria()
    nuevos_hechos = []
    
    # Simulación de extracción de hechos (en la v2 esto lo hace el LLM)
    palabras_clave = {
        "me gusta": "preferencia",
        "prefiero": "preferencia",
        "odio": "aversión",
        "mi meta es": "objetivo",
        "estoy trabajando en": "proyecto"
    }
    
    lineas = texto_conversacion.split("\n")
    for linea in lineas:
        for clave, categoria in palabras_clave.items():
            if clave in linea.lower():
                hecho = f"[{categoria}] {linea.strip()}"
                if hecho not in memoria["usuario"]["hechos_recordados"]:
                    nuevos_hechos.append(hecho)
    
    if nuevos_hechos:
        memoria["usuario"]["hechos_recordados"].extend(nuevos_hechos)
        memoria["relacion"]["interacciones_totales"] = memoria["relacion"].get("interacciones_totales", 0) + 1
        guardar_memoria(memoria)
        return True, nuevos_hechos
    
    return False, []

def main():
    if not os.path.exists(LOG_CONVERSACIONES):
        print("No hay logs de conversaciones para analizar.")
        return

    with open(LOG_CONVERSACIONES, "r", encoding="utf-8") as f:
        contenido = f.read()
    
    aprendio, hechos = analizar_y_aprender(contenido)
    if aprendio:
        print(f"CyberIA ha evolucionado. Nuevos hechos aprendidos: {hechos}")
    else:
        print("No se detectaron nuevos patrones de aprendizaje.")

if __name__ == "__main__":
    main()
