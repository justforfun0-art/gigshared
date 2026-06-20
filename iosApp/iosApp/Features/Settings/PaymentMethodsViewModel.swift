import Foundation
import Shared

/// Payment methods (beneficiaries) over the shared BeneficiaryRepository
/// (Android PaymentMethodsViewModel). List / add / set-primary / delete UPI or
/// bank accounts the worker gets paid into.
@MainActor
final class PaymentMethodsViewModel: ObservableObject {
    enum State { case idle, loading, loaded([Beneficiary]), failed(String) }

    @Published private(set) var state: State = .idle
    @Published var actionError: String?
    @Published var isSaving = false

    private let repo: any BeneficiaryRepository
    init(repo: any BeneficiaryRepository) { self.repo = repo }

    func load() async {
        state = .loading
        do {
            let list = try await IosHelpersKt.listBeneficiariesOrThrow(repo)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    func addUpi(holder: String, upiId: String, makePrimary: Bool) async -> Bool {
        await add(holder: holder, type: .upi, upiId: upiId, makePrimary: makePrimary)
    }

    func addBank(holder: String, accountNumber: String, ifsc: String, bankName: String, makePrimary: Bool) async -> Bool {
        await add(holder: holder, type: .bank, accountNumber: accountNumber,
                  ifsc: ifsc, bankName: bankName, makePrimary: makePrimary)
    }

    private func add(holder: String, type: AccountType, accountNumber: String? = nil,
                     ifsc: String? = nil, bankName: String? = nil, upiId: String? = nil,
                     makePrimary: Bool) async -> Bool {
        isSaving = true; actionError = nil
        defer { isSaving = false }
        do {
            _ = try await IosHelpersKt.addBeneficiaryOrThrow(
                repo, accountHolderName: holder, accountType: type,
                accountNumber: accountNumber, ifscCode: ifsc, bankName: bankName,
                upiId: upiId, phoneNumber: nil, isPrimary: makePrimary
            )
            await load()
            return true
        } catch {
            actionError = (error as NSError).localizedDescription
            return false
        }
    }

    func setPrimary(_ b: Beneficiary) async {
        actionError = nil
        do {
            try await IosHelpersKt.setPrimaryBeneficiaryOrThrow(repo, beneficiaryId: b.id)
            await load()
        } catch { actionError = (error as NSError).localizedDescription }
    }

    func delete(_ b: Beneficiary) async {
        actionError = nil
        do {
            try await IosHelpersKt.deleteBeneficiaryOrThrow(repo, beneficiaryId: b.id)
            await load()
        } catch { actionError = (error as NSError).localizedDescription }
    }
}
