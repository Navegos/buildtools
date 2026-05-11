// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: controller/main.rs
// created: 2026-05-06
// lastModified: 2026-05-06

slint::include_modules!();

use openidconnect::core::{CoreClient, CoreProviderMetadata, CoreResponseType};
use openidconnect::reqwest::async_http_client;
use openidconnect::{
    AuthenticationFlow, AuthorizationCode, ClientId, CsrfToken, IssuerUrl, Nonce,
    PkceCodeChallenge, RedirectUrl, Scope,
};
use std::process::Command;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::main]
async fn main() -> Result<(), slint::PlatformError> {
    let ui = ControlPanel::new()?;
    let ui_handle = ui.as_weak();

    // Setup Login Callback (Rauthy integration point)
    ui.on_login({
        let ui_handle = ui_handle.clone();
        move || {
            let ui = ui_handle.unwrap();
            ui.set_auth_status("Authenticating via Rauthy OIDC...".into());
            let ui_handle_clone = ui_handle.clone();
            
            tokio::spawn(async move {
                match perform_oidc_login().await {
                    Ok(_) => {
                        let _ = slint::invoke_from_event_loop(move || {
                            if let Some(ui) = ui_handle_clone.upgrade() {
                                ui.set_authenticated(true);
                                ui.set_auth_status("Authenticated Successfully".into());
                            }
                        });
                    }
                    Err(e) => {
                        eprintln!("Login failed: {}", e);
                        let _ = slint::invoke_from_event_loop(move || {
                            if let Some(ui) = ui_handle_clone.upgrade() {
                                ui.set_auth_status(format!("Auth Error: {}", e).into());
                            }
                        });
                    }
                }
            });
        }
    });

    // Setup Script Runner Callback
    ui.on_run_script(move |script_name| {
        println!("Requested to run: {}", script_name);
        println!("(TODO) Dispatching instruction to Master Node via Quinn...");
    });

    ui.run()
}

async fn perform_oidc_login() -> anyhow::Result<()> {
    let issuer_url = IssuerUrl::new("https://rauthy.localhost/auth/v1/ep".to_string())?;
    let provider_metadata = CoreProviderMetadata::discover_async(issuer_url, async_http_client).await?;

    let client = CoreClient::from_provider_metadata(
        provider_metadata,
        ClientId::new("buildtools-client".to_string()),
        None,
    )
    .set_redirect_uri(RedirectUrl::new("http://127.0.0.1:8080".to_string())?);

    let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();
    let (auth_url, _csrf_token, _nonce) = client
        .authorize_url(
            AuthenticationFlow::<CoreResponseType>::AuthorizationCode,
            CsrfToken::new_random,
            Nonce::new_random,
        )
        .add_scope(Scope::new("openid".to_string()))
        .add_scope(Scope::new("profile".to_string()))
        .set_pkce_challenge(pkce_challenge)
        .url();

    let url_str = auth_url.as_str();
    #[cfg(target_os = "windows")] Command::new("cmd").args(["/C", "start", url_str]).spawn()?;
    #[cfg(target_os = "macos")] Command::new("open").arg(url_str).spawn()?;
    #[cfg(target_os = "linux")] Command::new("xdg-open").arg(url_str).spawn()?;

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await?;
    let (mut stream, _) = listener.accept().await?;
    let mut buf = [0; 4096];
    stream.read(&mut buf).await?;
    let request = String::from_utf8_lossy(&buf);

    let mut code = None;
    if let Some(line) = request.lines().next() {
        if line.starts_with("GET /?") {
            if let Some(query) = line.split_whitespace().nth(1) {
                let full_url = format!("http://localhost{}", query);
                if let Ok(parsed_url) = url::Url::parse(&full_url) {
                    for (k, v) in parsed_url.query_pairs() {
                        if k == "code" { code = Some(v.into_owned()); }
                    }
                }
            }
        }
    }

    let response = "HTTP/1.1 200 OK\r\n\r\n<html><body>BuildTools Login successful! You can close this tab.</body></html>";
    stream.write_all(response.as_bytes()).await?;

    let code = code.ok_or_else(|| anyhow::anyhow!("Authorization code not found in redirect callback"))?;
    let _token_response = client.exchange_code(AuthorizationCode::new(code)).set_pkce_verifier(pkce_verifier).request_async(async_http_client).await?;

    Ok(())
}