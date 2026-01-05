# Chat Client - Flutter (E2EE)

Esta é a aplicação cliente do sistema de chat seguro, desenvolvida em **Flutter**. O aplicativo oferece uma interface gráfica para troca de mensagens com criptografia ponta-a-ponta (E2EE), garantindo que apenas os participantes da conversa tenham acesso ao conteúdo.

## Contexto Acadêmico

* **Instituição:** Universidade Federal Rural de Pernambuco (UFRPE) 
* **Unidade:** Unidade Acadêmica de Belo Jardim (UABJ) 
* **Disciplina:** Segurança da Informação 
* **Professor:** [Ygor Amaral](https://github.com/ygoramaral)

## Funcionalidades

* **Interface Moderna:** Desenvolvida em Flutter para uma experiência fluida.
* **Criptografia Ponta-a-Ponta (E2EE):** Implementação de AES-256 e HMAC-SHA256 para cada conversa entre usuários.
* **Handshake Seguro:** Negociação de chaves via Diffie-Hellman Efêmero (DHE).
* **Assinatura Digital:** Autenticação mútua entre usuários utilizando chaves assimétricas (RSA ou ECC).
* **Indicadores em Tempo Real:** Status online/offline e indicador de "digitando...".
* **Persistência Local:** Histórico de conversas armazenado localmente e criptografado com AES-256.

## Segurança Implementada

O cliente segue os requisitos de segurança do projeto:

* **Hashing:** Argon2 para proteção de senhas no registro.
* **Handshake:** Protocolo  para derivação de chaves de sessão.
* **Integridade:** Verificação de MAC (HMAC-SHA256) antes da descriptografia de qualquer mensagem.

## Configuração e Instalação

### Pré-requisitos

* Flutter SDK instalado (versão estável).
* Android Studio / VS Code com extensões Flutter/Dart.

### Configuração do Servidor

Para conectar o cliente ao seu servidor, você deve configurar o endereço IP correto.

1. Abra o arquivo: `lib/services/socket_service.dart`.
2. Altere a variável `serverHost` para o IP da sua máquina onde o servidor Docker está rodando:
```dart
static const String serverHost = '192.168.1.14'; // Altere para o seu IP

```

ou para rodar no emulador android:
```dart
static const String serverHost = '10.0.2.2'; // Altere para o IP padrão dos emuladores

```

### Como Rodar

1. Obtenha as dependências:
```bash
flutter pub get

```


2. Execute o projeto:
```bash
flutter run

```

## Download do APK

Você pode baixar a versão pronta para instalação diretamente na aba **Releases** deste repositório.

* Arquivo: `app-release.apk`
* Localização original da build: `build\app\outputs\flutter-apk\app-release.apk`

## Repositórios Relacionados

* **Repositório do Servidor (Python/Docker):** [Servidor Python](https://github.com/claraaqn/Servidor-Python)

---

**Desenvolvido por:** [Clara Aquino](https://github.com/claraaqn) Estudante de Engenharia da Computação 
