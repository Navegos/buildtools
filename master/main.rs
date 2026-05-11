// SPDX-FileCopyrightText: Copyright (c) 2026 Navegos. @DevelVitorF. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// project: buildtools
// file: master/main.rs
// created: 2026-05-07
// lastModified: 2026-05-06

use quinn::{Endpoint, ServerConfig};
use std::error::Error;
use std::net::SocketAddr;
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let addr: SocketAddr = "0.0.0.0:5000".parse().unwrap();
    let (server_config, _) = configure_server()?;
    let endpoint = Endpoint::server(server_config, addr)?;
    println!("Master node QUIC endpoint listening on {}", endpoint.local_addr()?);

    // Accept incoming worker and controller nodes
    while let Some(conn) = endpoint.accept().await {
        tokio::spawn(async move {
            if let Ok(connection) = conn.await {
                println!("Node connected from: {}", connection.remote_address());
                // Implement bidirectional stream parsing here to distribute builds
            }
        });
    }
    
    Ok(())
}

fn configure_server() -> Result<(ServerConfig, Vec<u8>), Box<dyn Error>> {
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])?;
    let cert_der = cert.serialize_der()?;
    let priv_key = rustls::pki_types::PrivateKeyDer::Pkcs8(cert.serialize_private_key_der().into());
    let cert_chain = vec![rustls::pki_types::CertificateDer::from(cert_der.clone())];
    
    let mut server_crypto = rustls::ServerConfig::builder().with_no_client_auth().with_single_cert(cert_chain, priv_key)?;
    server_crypto.alpn_protocols = vec![b"build-cluster".to_vec()];
    Ok((ServerConfig::with_crypto(Arc::new(server_crypto)), cert_der))
}
