// CasberiKeyAccount (spike, TESTNET ONLY).
//
// A private-only Aztec account whose signing key is a P-256 key (the phone's Secure Enclave), verified exactly like
// Aztec's EcdsaRAccount: P-256 over sha256(outer_hash), a 64-byte r||s auth witness. Unlike EcdsaRAccount:
//   * the signing key ROTATES: the current key signs a tx that calls `rotate_signing_key(new key)`;
//   * a separate RECOVERY P-256 key can replace the signing key through `recover(new key, nonce)`, which anyone may
//     submit (e.g. with no account at all, fees sponsored) but only the recovery key can authorise.
//
// There is no initializer and no public function, so nothing is ever deployed. The initial signing key and the
// recovery key are bound into the ADDRESS through the instance's `immutables_hash`
// (= poseidon2(initial.pack() ++ recovery.pack())). The current signing key lives in a SinglePrivateMutable note:
//   * the account's first authorised tx proves the initial key against the immutables and creates that note in the
//     same tx (its initialization nullifier makes the initial key usable exactly once, so a later attacker holding the
//     initial key cannot fall back to it);
//   * every later tx nullifies and re-creates the note (that is how a private read proves the note is CURRENT), so a
//     rotated-away key can never authorise again.
use aztec::macros::aztec;

#[aztec]
pub contract CasberiKeyAccount {
    use aztec::{
        authwit::{account::AccountActions, entrypoint::app::AppPayload},
        context::PrivateContext,
        history::note::assert_local_note_was_not_nullified_by,
        macros::{functions::{allow_phase_change, external, only_self, view}, storage::storage},
        messages::delivery::MessageDelivery,
        note::note_getter,
        oracle::{
            auth_witness::get_auth_witness_as_bytes,
            capsules::{load, store},
            get_contract_instance::get_contract_instance,
        },
        protocol::{hash::{poseidon2_hash, poseidon2_hash_bytes}, traits::{Packable, ToField}},
        state_vars::{SinglePrivateMutable, StateVariable},
    };

    use ecdsa_public_key_note::EcdsaPublicKeyNote;

    // Where the PXE keeps the immutables' preimage (both keys), written once by `register_keys`.
    global KEYS_SLOT: Field = comptime { poseidon2_hash_bytes("CASBERI_KEY_ACCOUNT_KEYS".as_bytes()) };
    global RECOVERY_DOMAIN: Field = comptime { poseidon2_hash_bytes("CASBERI_KEY_ACCOUNT_RECOVER".as_bytes()) };
    // An authwit check reads the key at the tx's anchor block; the tx may then live at most this long, so a key
    // rotated away stops authorising authwits within this window.
    global AUTHWIT_WINDOW_SECONDS: u64 = 600;

    #[storage]
    struct Storage<Context> {
        signing_key: SinglePrivateMutable<EcdsaPublicKeyNote, Context>,
    }

    // Local only (never a transaction): store both keys in this PXE, checked against the address.
    #[external("utility")]
    unconstrained fn register_keys(
        initial_x: [u8; 32],
        initial_y: [u8; 32],
        recovery_x: [u8; 32],
        recovery_y: [u8; 32],
    ) {
        let initial = EcdsaPublicKeyNote { x: initial_x, y: initial_y }.pack();
        let recovery = EcdsaPublicKeyNote { x: recovery_x, y: recovery_y }.pack();
        let data = [
            initial[0], initial[1], initial[2], initial[3], recovery[0], recovery[1], recovery[2], recovery[3],
        ];
        let instance = get_contract_instance(self.address);
        assert_eq(poseidon2_hash(data), instance.immutables_hash, "keys do not match this account's address");
        store(self.address, KEYS_SLOT, data, self.address);
    }

    #[external("private")]
    #[allow_phase_change]
    fn entrypoint(app_payload: AppPayload, fee_payment_method: u8, cancellable: bool) {
        let actions = AccountActions::init(self.context, is_valid_impl);
        actions.entrypoint(app_payload, fee_payment_method, cancellable);
    }

    #[external("private")]
    #[view]
    fn verify_private_authwit(inner_hash: Field) -> Field {
        let actions = AccountActions::init(self.context, is_valid_authwit_impl);
        actions.verify_private_authwit(inner_hash)
    }

    // The current key replaces itself. Reachable only through this account's own entrypoint, i.e. a tx the current
    // key already signed.
    #[external("private")]
    #[only_self]
    fn rotate_signing_key(new_x: [u8; 32], new_y: [u8; 32]) {
        let new_key = EcdsaPublicKeyNote { x: new_x, y: new_y };
        let this = self.address;
        self.storage.signing_key.replace(|_old| new_key, this).deliver(
            MessageDelivery::onchain_unconstrained().with_sender(this),
        );
    }

    // The recovery key replaces the signing key. Callable by anyone; authorised only by a recovery-key signature over
    // poseidon2(RECOVERY_DOMAIN, account, chain, version, new key, nonce), each message usable once.
    #[external("private")]
    fn recover(new_x: [u8; 32], new_y: [u8; 32], nonce: Field) {
        let this = self.address;
        let (_initial, recovery) = load_keys(self.context);
        let new_key = EcdsaPublicKeyNote { x: new_x, y: new_y };
        let p = new_key.pack();
        let message = poseidon2_hash(
            [
                RECOVERY_DOMAIN, this.to_field(), self.context.chain_id(), self.context.version(), p[0], p[1], p[2],
                p[3], nonce,
            ],
        );
        assert(p256_signed(recovery, message), "recovery signature invalid");
        // Single use: replaying the same recovery message fails on this nullifier.
        self.context.push_nullifier_unsafe(message);
        self.storage.signing_key.initialize_or_replace(|_old| new_key, this).deliver(
            MessageDelivery::onchain_unconstrained().with_sender(this),
        );
    }

    // Local only: the message a recovery key signs (a client should recompute it itself; this is a cross-check).
    #[external("utility")]
    unconstrained fn recovery_message(new_x: [u8; 32], new_y: [u8; 32], nonce: Field) -> Field {
        let p = EcdsaPublicKeyNote { x: new_x, y: new_y }.pack();
        poseidon2_hash(
            [
                RECOVERY_DOMAIN, self.address.to_field(), self.context.chain_id(), self.context.version(), p[0], p[1],
                p[2], p[3], nonce,
            ],
        )
    }

    #[contract_library_method]
    fn load_keys(context: &mut PrivateContext) -> (EcdsaPublicKeyNote, EcdsaPublicKeyNote) {
        let this = context.this_address();
        // Safety: the preimage is checked against the instance's immutables hash, which the address commits to.
        let data: [Field; 8] = unsafe { load(this, KEYS_SLOT, this) }.unwrap_or_else(|| {
            panic(f"account keys not registered in this PXE: call register_keys first")
        });
        let instance = get_contract_instance(this);
        assert_eq(poseidon2_hash(data), instance.immutables_hash, "keys do not match this account's address");
        (
            EcdsaPublicKeyNote::unpack([data[0], data[1], data[2], data[3]]),
            EcdsaPublicKeyNote::unpack([data[4], data[5], data[6], data[7]]),
        )
    }

    #[contract_library_method]
    fn p256_signed(key: EcdsaPublicKeyNote, message: Field) -> bool {
        // Safety: the witness only makes the verification below pass.
        let signature: [u8; 64] = unsafe { get_auth_witness_as_bytes(message) };
        let hashed_message: [u8; 32] = sha256::digest(message.to_be_bytes::<32>());
        std::ecdsa_secp256r1::verify_signature(key.x, key.y, signature, hashed_message)
    }

    // Entrypoint path: the first tx creates the key note from the initial key (proved against the immutables); every
    // later tx nullifies and re-creates the current note, proving it current.
    #[contract_library_method]
    fn is_valid_impl(context: &mut PrivateContext, outer_hash: Field) -> bool {
        let this = context.this_address();
        let (initial, _recovery) = load_keys(context);
        let storage = Storage::init(context);
        let message = storage.signing_key.initialize_or_replace(
            |current: Option<EcdsaPublicKeyNote>| current.unwrap_or(initial),
            this,
        );
        let key = message.get_note();
        message.deliver(MessageDelivery::onchain_unconstrained().with_sender(this));
        p256_signed(key, outer_hash)
    }

    // Authwit path (a static call: no nullifiers). Reads the current note, proves it was not nullified at the anchor
    // block, and caps the tx's lifetime so an anchor from before a rotation cannot be used for long. Requires the
    // key note to exist, i.e. the account has made at least one tx.
    #[contract_library_method]
    fn is_valid_authwit_impl(context: &mut PrivateContext, outer_hash: Field) -> bool {
        let storage = Storage::init(context);
        let slot = storage.signing_key.get_storage_slot();
        let anchor = context.get_anchor_block_header();
        let confirmed = note_getter::get_note::<EcdsaPublicKeyNote>(context, Option::none(), slot);
        assert_local_note_was_not_nullified_by(anchor, confirmed, context);
        context.set_expiration_timestamp(anchor.timestamp() + AUTHWIT_WINDOW_SECONDS);
        p256_signed(confirmed.note, outer_hash)
    }
}
