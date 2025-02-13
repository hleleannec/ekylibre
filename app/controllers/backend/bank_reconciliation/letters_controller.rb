module Backend
  module BankReconciliation
    # Handles bank reconciliation lettering.
    class LettersController < Backend::BaseController
      def create
        return unless find_cash

        bank_items     = BankStatementItem.where(id: params[:bank_statement_items])
        journal_items  = JournalEntryItem.where(id: params[:journal_entry_items])

        new_letter = @cash.letter_items(bank_items, journal_items)
        return head(:bad_request) unless new_letter

        respond_to do |format|
          format.json {  render json: { letter: new_letter } }
        end
      end

      def destroy
        return unless request.xhr? && find_cash

        letter = params[:letter]
        account_id = @cash.account_id
        cash_id = @cash.id

        if @cash.suspend_until_reconciliation
          bsi = BankStatementItem.joins(cash: :suspense_account)
            .where(letter: letter)
            .where('accounts.id = ?', account_id)
          # find all jeis on bank_statement_letter and account
          jeis = JournalEntryItem.where(bank_statement_letter: letter, account_id: account_id)
          # update bank_statement_letter on bsi and pointed jeis and letter on jeis
          bsi.update_all(letter: nil)
          jeis.update_all(bank_statement_letter: nil, bank_statement_id: nil, letter: nil)
          # update bank_statement_letter and letter on bsi_jeis
          bsi_jeis = JournalEntryItem.where(resource: bsi)
          bsi_jeis.update_all(bank_statement_letter: nil, bank_statement_id: nil, letter: nil)
        else
          bsi = BankStatementItem.joins(bank_statement: :cash).where("letter = ? AND bank_statements.cash_id = ?", letter, cash_id)
          jeis = JournalEntryItem.where(bank_statement_letter: letter, account_id: account_id)
          bsi.update_all(letter: nil)
          jeis.update_all(bank_statement_letter: nil, bank_statement_id: nil)
        end

        respond_to do |format|
          format.json { render json: { letter: letter } }
        end
      end

      private

        def find_cash
          @cash = Cash.find_by(id: params[:cash_id])
          @cash || (head(:bad_request) && nil)
        end
    end
  end
end
