# Resolving a claim token to its Grant, tenant-scoped — shared by the claim
# page and its download action. A signed token resolves globally, so a token
# minted for one press must never open a claim on another press's domain.
module ClaimScoped
  private
    def resolve_grant(token)
      grant = Grant.find_by_token_for(:claim, token)
      grant if grant && grant.account == Current.account
    end
end
