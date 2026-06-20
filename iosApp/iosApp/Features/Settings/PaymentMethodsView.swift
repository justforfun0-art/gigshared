import SwiftUI
import Shared

/// Payment Methods — port of Android's PaymentMethodsScreen. Lists the worker's
/// payout beneficiaries (UPI / bank), with add, set-primary, and delete.
struct PaymentMethodsView: View {
    let beneficiaries: any BeneficiaryRepository
    @StateObject private var viewModel: PaymentMethodsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    init(beneficiaries: any BeneficiaryRepository) {
        self.beneficiaries = beneficiaries
        _viewModel = StateObject(wrappedValue: PaymentMethodsViewModel(repo: beneficiaries))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("payment_methods_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("close")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showAdd) {
                AddPaymentMethodSheet(viewModel: viewModel)
            }
            .alert("Couldn’t complete that", isPresented: errorBinding) {
                Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .failed(let msg):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(msg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding()
        case .loaded(let list):
            if list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("payment_methods_empty")).font(.subheadline).foregroundStyle(.secondary)
                    Button(L("payment_methods_add")) { showAdd = true }.buttonStyle(.borderedProminent).tint(GHTheme.primary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(list, id: \.id) { b in
                        row(b)
                            .swipeActions {
                                Button(role: .destructive) { Task { await viewModel.delete(b) } } label: {
                                    Label(L("delete"), systemImage: "trash")
                                }
                                if !b.isPrimary {
                                    Button { Task { await viewModel.setPrimary(b) } } label: {
                                        Label(L("payment_methods_make_primary"), systemImage: "star")
                                    }.tint(GHTheme.primary)
                                }
                            }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func row(_ b: Beneficiary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: b.accountType == .upi ? "qrcode" : "building.columns")
                .font(.title3).foregroundStyle(GHTheme.primary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.accountHolderName).font(.subheadline.weight(.semibold))
                Text(subtitle(b)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if b.isPrimary {
                Text(L("payment_methods_primary")).font(.caption2.weight(.bold))
                    .foregroundStyle(GHTheme.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(GHTheme.success.opacity(0.12), in: Capsule())
            }
        }
    }

    private func subtitle(_ b: Beneficiary) -> String {
        if b.accountType == .upi { return b.upiId ?? "UPI" }
        let masked = (b.accountNumber.map { "••••" + String($0.suffix(4)) }) ?? ""
        return [b.bankName, masked].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Add UPI / bank beneficiary.
private struct AddPaymentMethodSheet: View {
    @ObservedObject var viewModel: PaymentMethodsViewModel
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable { case upi = "UPI", bank = "Bank" }
    @State private var kind: Kind = .upi
    @State private var holder = ""
    @State private var upiId = ""
    @State private var accountNumber = ""
    @State private var ifsc = ""
    @State private var bankName = ""
    @State private var makePrimary = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                Section {
                    TextField(L("payment_methods_holder"), text: $holder)
                }
                if kind == .upi {
                    Section(L("wallet_upi_label")) {
                        TextField("name@bank", text: $upiId)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } else {
                    Section(L("payment_methods_bank")) {
                        TextField(L("payment_methods_account_no"), text: $accountNumber).keyboardType(.numberPad)
                        TextField("IFSC", text: $ifsc).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        TextField(L("payment_methods_bank_name"), text: $bankName)
                    }
                }
                Section {
                    Toggle(L("payment_methods_make_primary"), isOn: $makePrimary)
                }
            }
            .navigationTitle(L("payment_methods_add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel_filter")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("save")) { Task { await save() } }.disabled(viewModel.isSaving || !valid)
                }
            }
        }
    }

    private var valid: Bool {
        guard !holder.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return kind == .upi
            ? !upiId.trimmingCharacters(in: .whitespaces).isEmpty
            : !accountNumber.isEmpty && !ifsc.isEmpty
    }

    private func save() async {
        let ok: Bool
        if kind == .upi {
            ok = await viewModel.addUpi(holder: holder, upiId: upiId, makePrimary: makePrimary)
        } else {
            ok = await viewModel.addBank(holder: holder, accountNumber: accountNumber,
                                         ifsc: ifsc, bankName: bankName, makePrimary: makePrimary)
        }
        if ok { dismiss() }
    }
}
