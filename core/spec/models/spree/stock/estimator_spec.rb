require 'spec_helper'

module Spree
  module Stock
    describe Estimator do
      let!(:shipping_method) { create(:shipping_method) }
      let(:package) { build(:stock_package_fulfilled) }
      let(:order) { package.order }
      subject { Estimator.new(order) }

      context "#shipping rates" do
        before(:each) do
          shipping_method.zones.first.members.create(:zoneable => order.ship_address.country)
          ShippingMethod.any_instance.stub_chain(:calculator, :available?).and_return(true)
          ShippingMethod.any_instance.stub_chain(:calculator, :compute).and_return(4.00)
          ShippingMethod.any_instance.stub_chain(:calculator, :preferences).and_return({:currency => "USD"})

          package.stub(:shipping_methods => [shipping_method])
        end

        it "returns shipping rates from a shipping" do
          shipping_rates = subject.shipping_rates(package)
          shipping_rates.first.cost.should eq 4.00
        end

        it "sorts shipping rates by cost" do
          shipping_methods = 3.times.map { create(:shipping_method) }
          shipping_methods[0].stub_chain(:calculator, :compute).and_return(5.00)
          shipping_methods[1].stub_chain(:calculator, :compute).and_return(3.00)
          shipping_methods[2].stub_chain(:calculator, :compute).and_return(4.00)

          subject.stub(:shipping_methods).and_return(shipping_methods)

          expect(subject.shipping_rates(package).map(&:cost)).to eq %w[3.00 4.00 5.00].map(&BigDecimal.method(:new))
        end

        context "general shipping methods" do
          let(:shipping_methods) { 2.times.map { create(:shipping_method) } }
          before do
            subject.stub(:shipping_methods).and_return(shipping_methods)

            shipping_methods[0].stub_chain(:calculator, :compute).and_return(5.00)
            shipping_methods[1].stub_chain(:calculator, :compute).and_return(3.00)
          end

          it "selects the most affordable shipping rate" do
            expect(subject.shipping_rates(package).sort_by(&:cost).map(&:selected)).to eq [true, false]
          end

          context "nil shipping rates" do
            before { shipping_methods[1].stub_chain(:calculator, :compute) { nil } }

            it "discards nil shipping rates to avoid *accidentally* offering free shipping" do
              expect(subject.shipping_rates(package).count).to eq 1
            end
          end

          context "zero shipping rates" do
            before { shipping_methods[1].stub_chain(:calculator, :compute) { 0 } }

            it "preserves $0 shipping rates, trusting the calculator to offer free shipping if desired" do
              expect(subject.shipping_rates(package).sort_by(&:cost).map(&:selected)).to eq [true, false]
            end
          end
        end

        context "involves backend only shipping methods" do
          let(:backend_method) { create(:shipping_method, display_on: "back_end") }
          let(:generic_method) { create(:shipping_method) }

          # regression for #3287
          it "doesn't select backend rates even if they're more affordable" do
            backend_method.stub_chain(:calculator, :compute).and_return(0.00)
            generic_method.stub_chain(:calculator, :compute).and_return(5.00)

            subject.stub(:shipping_methods).and_return([backend_method, generic_method])

            expect(subject.shipping_rates(package).map(&:selected)).to eq [false, true]
          end
        end
      end
    end
  end
end
