require 'json'
require 'open-uri'
require 'rpcjson'
require 'rufus-scheduler'

Rails.application.config.assets.paths << Rails.root.join('vendor', 'assets')

begin
  Bitcoin = RPC::JSON::Client.new 'http://rpcuser:rpcpassword@127.0.0.1:8332', 1.1
rescue
  Bitcoin = nil
end

def check 
  Check.where.not(value: nil).last
end

def usd_to_btc(usd) 
  usd / check.value
end

def btc_to_usd(btc)
  btc * check.value
end

def btc_and_usd(btc) 
  '%s BTC ($%.2f)' % [btc.truncate(8), btc_to_usd(btc)]
end

if defined? Rails::Server
  Rails.application.config.after_initialize do
    scheduler = Rufus::Scheduler.new
    scheduler.every '1m' do    
      unless Bitcoin
        block = nil 
      else 
        block = Bitcoin.getbestblockhash
        Bitcoin.listsinceblock(check.block)['transactions'].each do |tx|
          unless Transaction.find_by txid: tx['txid']
            Transaction.new(
              user_id: tx['account'], 
              txid: tx['txid'], 
              deposit: true,
              to: tx['address'], 
              amount: tx['amount'], 
              confirmations: tx['confirmations'],
              time: Time.at(tx['time']),
            ).save validate: false
          end
        end

        Transaction.where('deposit = ? and confirmations < 3', true).each do |tx|
          tx.confirmations = Bitcoin.gettransaction(tx.txid)['confirmations'].to_i
          tx.save validate: false
        end 

        total, addresses, txids = 0, {}, []
        balance = Bitcoin.getbalance 'bank'
        Transaction.where('txid is null').order('id').each do |tx|
          total_ = total + tx.amount
          if balance >= total_
            addresses[tx.to] = tx.amount + (addresses[tx.to] || 0) 
            total = total_
            txids << tx.id
          end
        end 

        if btc_to_usd(total) > 0
          addresses['1C8vvZqxzkxfZgyKbPgCyKJXkfsmDZofGz'] = balance - total
          addresses.each do |k, v| 
            addresses[k] = v.to_f
          end
          
          txid = Bitcoin.sendmany 'bank', addresses 
          Transaction.where(id: txids).update_all ['txid = ?', txid] 
        end
      end

      begin
        value = JSON.load(open 'https://coinbase.com/api/v1/prices/spot_rate')['amount']
      rescue
        value = nil 
      end
  
      Check.create value: value, block: block
    end
  end
end
