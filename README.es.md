<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# oryksa

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-30363d?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-0891b2?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-30363d?style=for-the-badge)](README.fr.md)

SDK oficial de Flutter de **ORYKSA AI Employees**: pon en tu app un empleado de IA que ya conoce tu negocio, con un chat listo igual al chat de la web de ORYKSA, con el nombre y la foto de tu IA.

1. Tu **servidor** guarda la clave secreta y crea un token de sesión para cada usuario (`POST /v1/sessions`).
2. La **app** usa solo ese token: `OryksaClient(getToken: ...)` y `OryksaChatButton(client: client, lang: 'es')`.
3. **Burbuja en la barra de pestañas (1.2):** cambia tu `NavigationBar` por `OryksaBottomBar(client: client, ...)` y la foto de tu IA queda en el centro de la barra. Al tocarla se abre el chat con voz: pantalla completa en el móvil, panel lateral en pantallas anchas. En una barra propia, usa `OryksaTabBubble(client: client)`.
4. Cada respuesta de la IA cuenta como una interacción de tu plan.
5. Las funciones de servidor (clave secreta, cambiar la IA y el Brain, webhooks) están en una biblioteca aparte, `package:oryksa/oryksa_server.dart`, solo para tu servidor. Nunca la importes en la app.

## Instalar

```bash
flutter pub add oryksa
```

**Documentación completa:** https://developer.oryksa.com/es/sdk-flutter

---

## Sobre el autor

**Weslley Harakawa** - Fundador de ORYKSA AI. En Lisboa, Portugal. Especialidades: inteligencia artificial, desarrollo web y móvil, tokenización en blockchain. Formación: University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSAAI)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda
