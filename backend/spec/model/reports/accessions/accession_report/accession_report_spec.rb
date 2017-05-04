require_relative "../../../../../app/model/reports/abstract_report.rb"
require_relative "../../../../../app/model/reports/accessions/accession_report/accession_report.rb"

describe 'Accession Report' do
  it "registers the report" do
    puts "it runs"
    abs_rpt = AccessionReport.new({}, "", "")
    puts abs_rpt.inspect   #should_receive(ReportManager::register_report).with(:any_args).once
  end
  it "has a corresponding template" do
    abs_rpt = AccessionReport.new({}, "", "")
    expect(abs_rpt.template).to eq("accession_report.erb")
  end
  it "performs a query" do
    # DB = Sequel.mock(:fetch=>[{:id => 1, :name =>2}])
    # puts DB.inspect
  end
end
