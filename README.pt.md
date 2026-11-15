<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# oryksa

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-0891b2?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-30363d?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-30363d?style=for-the-badge)](README.fr.md)

SDK oficial Flutter da **ORYKSA AI Employees**: põe na tua app um colaborador de IA que já conhece o teu negócio, com um chat pronto igual ao chat do site da ORYKSA, com o nome e a foto da tua IA.

1. O teu **servidor** guarda a chave secreta e cria um token de sessão para cada utilizador (`POST /v1/sessions`).
2. A **app** usa só esse token: `OryksaClient(getToken: ...)` e `OryksaChatButton(client: client, lang: 'pt')`.
3. **Bolinha na barra de separadores (1.2):** troca o teu `NavigationBar` por `OryksaBottomBar(client: client, ...)` e a foto da tua IA fica no meio da barra. Ao tocar abre o chat com voz: ecrã inteiro no telemóvel, painel lateral em ecrãs largos. Numa barra tua, usa `OryksaTabBubble(client: client)`.
4. Cada resposta da IA conta como uma interação do teu plano.
5. As funções de servidor (chave secreta, alterar a IA e o Brain, webhooks) estão numa biblioteca à parte, `package:oryksa/oryksa_server.dart`, só para o teu servidor. Nunca a importes na app.

## Instalar

```bash
flutter pub add oryksa
```

**Documentação completa:** https://developer.oryksa.com/pt/sdk-flutter

---

## Sobre o autor

**Weslley Harakawa** - Fundador da ORYKSA AI. Em Lisboa, Portugal. Especialidades: inteligência artificial, desenvolvimento web e mobile, tokenização em blockchain. Formação: University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSAAI)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda
